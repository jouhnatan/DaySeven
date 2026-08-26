//! The workspace CRDT, as Dart sees it.
//!
//! Documents live in a registry behind integer handles rather than crossing the
//! FFI boundary as opaque objects. That keeps the bridge free of lifetime and
//! `Send` questions, and makes the Dart side a plain value type it can hold in
//! a Riverpod provider.
//!
//! The shape mirrors the plan exactly:
//!
//! ```text
//! files: Y.Map<fileId, Y.Map{ path, protected, owners: Y.Array, content: Y.Text }>
//! workspaceMeta: Y.Map{ workspaceId, schemaVersion }
//! ```

use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};

use yrs::types::{Event, PathSegment};
use yrs::{Assoc, IndexedSequence, StickyIndex};
use yrs::updates::decoder::Decode;
use yrs::updates::encoder::Encode;
use yrs::{
    Any, Array, ArrayPrelim, DeepObservable, Doc, GetString, Map, MapPrelim, MapRef, OffsetKind,
    Options, Out, ReadTxn, StateVector, Text, TextPrelim, TextRef, Transact, Update,
};

/// Bumped when the on-disk layout of `workspace.bin` changes in a way older
/// builds cannot read. Loading refuses anything it does not recognise rather
/// than applying a partial document.
pub const SCHEMA_VERSION: i64 = 1;

const FILES: &str = "files";
const META: &str = "workspaceMeta";
const KEY_PATH: &str = "path";
const KEY_PROTECTED: &str = "protected";
const KEY_OWNERS: &str = "owners";
const KEY_CONTENT: &str = "content";

static REGISTRY: OnceLock<Mutex<HashMap<u64, Doc>>> = OnceLock::new();
static NEXT_HANDLE: AtomicU64 = AtomicU64::new(1);

fn registry() -> &'static Mutex<HashMap<u64, Doc>> {
    REGISTRY.get_or_init(|| Mutex::new(HashMap::new()))
}

fn with_doc<T>(handle: u64, f: impl FnOnce(&Doc) -> T) -> Result<T, String> {
    let guard = registry().lock().map_err(|_| "registry poisoned".to_string())?;
    let doc = guard
        .get(&handle)
        .ok_or_else(|| format!("no open workspace with handle {handle}"))?;
    Ok(f(doc))
}

/// Every document in DaySeven is created here, and always with UTF-16 offsets.
///
/// `yrs` defaults to `OffsetKind::Bytes`, but Yjs indexes text in UTF-16. Two
/// things break on the default: text offsets disagree with Dart's own string
/// indexing the moment a document contains non-ASCII (the tree already holds
/// `Oetes [\u03a9\u03b5\u03c4\u03b5\u03c2].md`), and updates stop being interchangeable with a
/// real Yjs peer. Both documents in a sync pair must agree, so this must be the
/// only place a `Doc` is constructed.
fn new_doc() -> Doc {
    Doc::with_options(Options {
        offset_kind: OffsetKind::Utf16,
        ..Options::default()
    })
}

fn insert(doc: Doc) -> u64 {
    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    registry().lock().unwrap().insert(handle, doc);
    handle
}

/// Metadata about one file, without its text.
pub struct FileMeta {
    pub file_id: String,
    pub path: String,
    pub protected: bool,
    pub owners: Vec<String>,
}

// ---------------------------------------------------------------- lifecycle

/// Creates an empty workspace and returns its handle.
pub fn workspace_create(workspace_id: String) -> u64 {
    let doc = new_doc();
    {
        let meta = doc.get_or_insert_map(META);
        let _ = doc.get_or_insert_map(FILES);
        let mut txn = doc.transact_mut();
        meta.insert(&mut txn, "workspaceId", workspace_id);
        meta.insert(&mut txn, "schemaVersion", SCHEMA_VERSION);
    }
    insert(doc)
}

/// Loads `workspace.bin`.
///
/// Refuses a document whose `schemaVersion` this build does not understand,
/// rather than applying it partially and silently losing the parts it cannot
/// represent.
pub fn workspace_load(bytes: Vec<u8>) -> Result<u64, String> {
    let doc = new_doc();
    let _ = doc.get_or_insert_map(FILES);
    let meta = doc.get_or_insert_map(META);
    {
        let update = Update::decode_v1(&bytes).map_err(|e| format!("malformed workspace: {e}"))?;
        let mut txn = doc.transact_mut();
        txn.apply_update(update)
            .map_err(|e| format!("could not apply workspace: {e}"))?;
    }

    let version = {
        let txn = doc.transact();
        match meta.get(&txn, "schemaVersion") {
            Some(v) => match as_i64(v) {
                Some(n) => n,
                None => return Err("workspace has a non-numeric schemaVersion".into()),
            },
            // A document written before the key existed; treat as current.
            None => SCHEMA_VERSION,
        }
    };
    if version > SCHEMA_VERSION {
        return Err(format!(
            "this Knowledge Base was written by a newer version of DaySeven \
             (schema {version}, this build understands {SCHEMA_VERSION})"
        ));
    }

    Ok(insert(doc))
}

/// Releases a workspace. Handles are not reused.
pub fn workspace_close(handle: u64) {
    registry().lock().unwrap().remove(&handle);
}

pub fn workspace_id(handle: u64) -> Result<String, String> {
    with_doc(handle, |doc| {
        let meta = doc.get_or_insert_map(META);
        let txn = doc.transact();
        meta.get(&txn, "workspaceId")
            .and_then(as_string)
            .unwrap_or_default()
    })
}

// ------------------------------------------------------------------- sync

/// The full document, for writing `workspace.bin`.
pub fn workspace_encode(handle: u64) -> Result<Vec<u8>, String> {
    with_doc(handle, |doc| {
        doc.transact()
            .encode_state_as_update_v1(&StateVector::default())
    })
}

/// This peer's state vector, which the other side needs to compute a diff.
pub fn workspace_state_vector(handle: u64) -> Result<Vec<u8>, String> {
    with_doc(handle, |doc| doc.transact().state_vector().encode_v1())
}

/// Only what the peer at `since_state_vector` is missing.
///
/// This is what rides Realtime broadcast. Measured at 32-35 bytes for a
/// single-paragraph edit, against a 256 KB payload cap.
pub fn workspace_diff(handle: u64, since_state_vector: Vec<u8>) -> Result<Vec<u8>, String> {
    let sv = StateVector::decode_v1(&since_state_vector)
        .map_err(|e| format!("malformed state vector: {e}"))?;
    with_doc(handle, |doc| doc.transact().encode_state_as_update_v1(&sv))
}

/// Applies a remote update and reports which file ids it touched.
///
/// The returned ids are what the protected-file gate inspects: an update that
/// touches a protected file the sender may not write is rejected before it
/// reaches canonical state. Callers that need that guarantee must apply to a
/// staging workspace first — see `workspace_stage_apply`.
pub fn workspace_apply(handle: u64, update: Vec<u8>) -> Result<Vec<String>, String> {
    let update = Update::decode_v1(&update).map_err(|e| format!("malformed update: {e}"))?;
    let guard = registry().lock().map_err(|_| "registry poisoned".to_string())?;
    let doc = guard
        .get(&handle)
        .ok_or_else(|| format!("no open workspace with handle {handle}"))?;

    let touched = Arc::new(Mutex::new(Vec::<String>::new()));
    let sink = touched.clone();
    let files = doc.get_or_insert_map(FILES);
    let subscription = files.observe_deep(move |txn, events| {
        let mut out = sink.lock().unwrap();
        for event in events.iter() {
            match event.path().front() {
                // A change *inside* one file — its text, path, or owners. The
                // first path segment is the file id.
                Some(PathSegment::Key(key)) => {
                    let id = key.to_string();
                    if !out.contains(&id) {
                        out.push(id);
                    }
                }
                // A change to the `files` map itself: a file created or
                // removed. Here the path is empty and the ids are the event's
                // changed keys. Missing this case meant a collaborator's *new*
                // document synced into the CRDT and was never reported, so it
                // was never materialised to Markdown.
                None => {
                    if let Event::Map(map_event) = event {
                        for key in map_event.keys(txn).keys() {
                            let id = key.to_string();
                            if !out.contains(&id) {
                                out.push(id);
                            }
                        }
                    }
                }
                _ => {}
            }
        }
    });

    {
        let mut txn = doc.transact_mut();
        txn.apply_update(update)
            .map_err(|e| format!("could not apply update: {e}"))?;
    }
    drop(subscription);

    let touched = touched.lock().unwrap().clone();
    Ok(touched)
}

/// Applies an update to a throwaway copy and reports the file ids it would
/// touch, without changing canonical state.
///
/// This is the authorization gate: inspect first, decide, then either apply for
/// real or route the change into a proposal.
pub fn workspace_stage_apply(handle: u64, update: Vec<u8>) -> Result<Vec<String>, String> {
    let base = workspace_encode(handle)?;
    let staging = workspace_load(base)?;
    let result = workspace_apply(staging, update);
    workspace_close(staging);
    result
}

// ------------------------------------------------------- awareness cursors

/// Encodes a caret position inside a file's text as a Yjs *relative* position.
///
/// An absolute index is meaningless to a collaborator: by the time it reaches
/// them, their copy has moved, and index 40 in their document is somewhere
/// else entirely. A relative position is anchored to the character it sits
/// beside, so it survives concurrent editing and lands where the person
/// actually is.
///
/// `index` is a UTF-16 offset, matching Dart's string indexing and the
/// `OffsetKind::Utf16` every document here is built with.
///
/// Returns an empty vector when the file has no text yet, which is a caret at
/// the start of nothing rather than an error.
pub fn text_relative_position(
    handle: u64,
    file_id: String,
    index: u32,
) -> Result<Vec<u8>, String> {
    let found = with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        // One transaction throughout. `sticky_index` needs a mutable one, and
        // opening a second inside a read transaction deadlocks the document.
        let mut txn = doc.transact_mut();
        let text = text_ref(&files, &txn, &file_id)?;
        Some(
            text.sticky_index(&mut txn, index, Assoc::After)
                .map(|p| p.encode_v1())
                .unwrap_or_default(),
        )
    })?;
    found.ok_or_else(|| format!("no file {file_id} in this workspace"))
}

/// Resolves a collaborator's relative position into an index in *this* copy.
///
/// When the character the position was anchored to has since been deleted,
/// `yrs` resolves to where that text used to be rather than giving up, so a
/// caret in a deleted paragraph collapses to the point the paragraph occupied
/// instead of disappearing. That is the better behaviour for drawing a cursor,
/// but it means the result is a *hint*, not a guarantee: callers must still
/// clamp it against the length of their own copy before using it.
///
/// `None` means the position could not be resolved at all — an empty position,
/// or a document that no longer holds the branch it referred to.
pub fn text_absolute_index(
    handle: u64,
    file_id: String,
    position: Vec<u8>,
) -> Result<Option<u32>, String> {
    if position.is_empty() {
        return Ok(None);
    }
    let sticky = StickyIndex::decode_v1(&position)
        .map_err(|e| format!("malformed relative position: {e}"))?;
    let found = with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let txn = doc.transact();
        text_ref(&files, &txn, &file_id).map(|_| {
            sticky
                .get_offset(&txn)
                .map(|offset| offset.index)
        })
    })?;
    found.ok_or_else(|| format!("no file {file_id} in this workspace"))
}

// ------------------------------------------------------------------ files

pub fn file_ids(handle: u64) -> Result<Vec<String>, String> {
    with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let txn = doc.transact();
        files.iter(&txn).map(|(k, _)| k.to_string()).collect()
    })
}

/// Creates the file if it is not already present. Existing content is left
/// alone, so this is safe to call on every scan.
pub fn file_upsert(
    handle: u64,
    file_id: String,
    path: String,
    protected: bool,
    owners: Vec<String>,
) -> Result<(), String> {
    with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let mut txn = doc.transact_mut();
        match files.get(&txn, &file_id).and_then(|v| v.cast::<MapRef>().ok()) {
            Some(existing) => {
                existing.insert(&mut txn, KEY_PATH, path);
                existing.insert(&mut txn, KEY_PROTECTED, protected);
                existing.insert(&mut txn, KEY_OWNERS, ArrayPrelim::from(owners));
            }
            None => {
                let entry = files.insert(&mut txn, file_id, MapPrelim::default());
                entry.insert(&mut txn, KEY_PATH, path);
                entry.insert(&mut txn, KEY_PROTECTED, protected);
                entry.insert(&mut txn, KEY_OWNERS, ArrayPrelim::from(owners));
                entry.insert(&mut txn, KEY_CONTENT, TextPrelim::new(""));
            }
        }
    })
}

pub fn file_remove(handle: u64, file_id: String) -> Result<(), String> {
    with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let mut txn = doc.transact_mut();
        files.remove(&mut txn, &file_id);
    })
}

pub fn file_text(handle: u64, file_id: String) -> Result<String, String> {
    let found = with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let txn = doc.transact();
        text_ref(&files, &txn, &file_id).map(|t| t.get_string(&txn))
    })?;
    found.ok_or_else(|| format!("no file {file_id} in this workspace"))
}

pub fn file_meta(handle: u64, file_id: String) -> Result<FileMeta, String> {
    let found = with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let txn = doc.transact();
        let entry = files.get(&txn, &file_id)?.cast::<MapRef>().ok()?;
        let path = entry.get(&txn, KEY_PATH).and_then(as_string).unwrap_or_default();
        let protected = entry.get(&txn, KEY_PROTECTED).map(as_bool).unwrap_or(false);
        let owners = entry
            .get(&txn, KEY_OWNERS)
            .and_then(|v| v.cast::<yrs::ArrayRef>().ok())
            .map(|arr| arr.iter(&txn).filter_map(as_string).collect::<Vec<_>>())
            .unwrap_or_default();
        Some(FileMeta {
            file_id: file_id.clone(),
            path,
            protected,
            owners,
        })
    })?;
    found.ok_or_else(|| format!("no file {file_id} in this workspace"))
}

/// Reconciles `Y.Text` toward `next` **without replacing it**.
///
/// A wholesale replace would destroy every concurrent edit and every collaborator's
/// cursor, so the common prefix and suffix are preserved and only the differing
/// span is rewritten. For the ordinary case — someone typing, or an external
/// editor changing one region — that is a minimal edit. A change scattered
/// across a file collapses into one wider span, which is still correct, just
/// coarser than an optimal diff.
///
/// Offsets are in UTF-16 code units, which is what `Y.Text` indexes by and what
/// Dart strings use.
pub fn file_set_text(handle: u64, file_id: String, next: String) -> Result<(), String> {
    let applied = with_doc(handle, |doc| {
        let files = doc.get_or_insert_map(FILES);
        let mut txn = doc.transact_mut();
        let Some(text) = text_ref(&files, &txn, &file_id) else {
            return false;
        };

        let current: Vec<u16> = text.get_string(&txn).encode_utf16().collect();
        let target: Vec<u16> = next.encode_utf16().collect();
        if current == target {
            return true;
        }

        let mut prefix = 0usize;
        let max_prefix = current.len().min(target.len());
        while prefix < max_prefix && current[prefix] == target[prefix] {
            prefix += 1;
        }

        let mut suffix = 0usize;
        let max_suffix = max_prefix - prefix;
        while suffix < max_suffix
            && current[current.len() - 1 - suffix] == target[target.len() - 1 - suffix]
        {
            suffix += 1;
        }

        let removed = current.len() - prefix - suffix;
        if removed > 0 {
            text.remove_range(&mut txn, prefix as u32, removed as u32);
        }
        if target.len() - prefix - suffix > 0 {
            let inserted = String::from_utf16_lossy(&target[prefix..target.len() - suffix]);
            text.insert(&mut txn, prefix as u32, &inserted);
        }
        true
    })?;

    if applied {
        Ok(())
    } else {
        Err(format!("no file {file_id} in this workspace"))
    }
}

/// `Out` is yrs's value union; only the `Any` arm carries a scalar.
fn as_string(value: Out) -> Option<String> {
    match value {
        Out::Any(Any::String(s)) => Some(s.to_string()),
        _ => None,
    }
}

fn as_bool(value: Out) -> bool {
    matches!(value, Out::Any(Any::Bool(true)))
}

fn as_i64(value: Out) -> Option<i64> {
    match value {
        Out::Any(Any::BigInt(n)) => Some(n),
        Out::Any(Any::Number(n)) => Some(n as i64),
        _ => None,
    }
}

fn text_ref<T: ReadTxn>(files: &MapRef, txn: &T, file_id: &str) -> Option<TextRef> {
    files
        .get(txn, file_id)?
        .cast::<MapRef>()
        .ok()?
        .get(txn, KEY_CONTENT)?
        .cast::<TextRef>()
        .ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    const FILE: &str = "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1";

    fn workspace_with_file(text: &str) -> u64 {
        let ws = workspace_create("awayside".into());
        file_upsert(
            ws,
            FILE.into(),
            "Characters/Aldric.md".into(),
            false,
            vec!["haoyu".into()],
        )
        .unwrap();
        file_set_text(ws, FILE.into(), text.into()).unwrap();
        ws
    }

    #[test]
    fn workspace_bin_round_trips() {
        let a = workspace_with_file("The moor is wide.");
        let bin = workspace_encode(a).unwrap();

        let b = workspace_load(bin).unwrap();
        assert_eq!(file_text(b, FILE.into()).unwrap(), "The moor is wide.");
        assert_eq!(workspace_id(b).unwrap(), "awayside");

        let meta = file_meta(b, FILE.into()).unwrap();
        assert_eq!(meta.path, "Characters/Aldric.md");
        assert!(!meta.protected);
        assert_eq!(meta.owners, vec!["haoyu".to_string()]);
    }

    #[test]
    fn concurrent_edits_converge() {
        let a = workspace_with_file("The moor is wide.");
        let b = workspace_load(workspace_encode(a).unwrap()).unwrap();

        // Both edit different regions without seeing each other.
        file_set_text(a, FILE.into(), "The wide moor is wide.".into()).unwrap();
        file_set_text(b, FILE.into(), "The moor is wide. Aldenmoor.".into()).unwrap();

        let a_to_b = workspace_diff(a, workspace_state_vector(b).unwrap()).unwrap();
        let b_to_a = workspace_diff(b, workspace_state_vector(a).unwrap()).unwrap();
        workspace_apply(b, a_to_b).unwrap();
        workspace_apply(a, b_to_a).unwrap();

        let left = file_text(a, FILE.into()).unwrap();
        let right = file_text(b, FILE.into()).unwrap();
        assert_eq!(left, right, "peers diverged");
        // Neither edit was lost.
        assert!(left.contains("wide moor"), "lost A's edit: {left}");
        assert!(left.contains("Aldenmoor"), "lost B's edit: {left}");
    }

    #[test]
    fn set_text_preserves_a_concurrent_edit_elsewhere() {
        // The reason file_set_text must not replace the whole Y.Text: an
        // external editor rewriting one paragraph must not discard a
        // collaborator's simultaneous edit to another.
        let a = workspace_with_file("alpha bravo charlie");
        let b = workspace_load(workspace_encode(a).unwrap()).unwrap();

        file_set_text(a, FILE.into(), "alpha BRAVO charlie".into()).unwrap();
        file_set_text(b, FILE.into(), "alpha bravo DELTA".into()).unwrap();

        let a_to_b = workspace_diff(a, workspace_state_vector(b).unwrap()).unwrap();
        workspace_apply(b, a_to_b).unwrap();

        let merged = file_text(b, FILE.into()).unwrap();
        assert!(merged.contains("BRAVO"), "lost the remote edit: {merged}");
        assert!(merged.contains("DELTA"), "lost the local edit: {merged}");
    }

    #[test]
    fn staging_reports_touched_files_without_mutating_canonical() {
        let a = workspace_with_file("The moor is wide.");
        let b = workspace_load(workspace_encode(a).unwrap()).unwrap();

        file_set_text(b, FILE.into(), "The moor is wide and cold.".into()).unwrap();
        let update = workspace_diff(b, workspace_state_vector(a).unwrap()).unwrap();

        let touched = workspace_stage_apply(a, update.clone()).unwrap();
        assert_eq!(touched, vec![FILE.to_string()]);
        // Canonical state is untouched: the gate has not decided yet.
        assert_eq!(file_text(a, FILE.into()).unwrap(), "The moor is wide.");

        // Applying for real does move it.
        workspace_apply(a, update).unwrap();
        assert_eq!(
            file_text(a, FILE.into()).unwrap(),
            "The moor is wide and cold."
        );
    }

    #[test]
    fn unicode_offsets_are_utf16_safe() {
        // Y.Text indexes in UTF-16, and the tree has documents like
        // "Oetes [Ωετες].md". Getting this wrong corrupts text silently.
        let ws = workspace_with_file("Oetes [Ωετες] holds");
        file_set_text(ws, FILE.into(), "Oetes [Ωετες] holds fast".into()).unwrap();
        assert_eq!(
            file_text(ws, FILE.into()).unwrap(),
            "Oetes [Ωετες] holds fast"
        );

        file_set_text(ws, FILE.into(), "Oetes [Ω] holds fast".into()).unwrap();
        assert_eq!(file_text(ws, FILE.into()).unwrap(), "Oetes [Ω] holds fast");
    }

    #[test]
    fn malformed_workspace_is_refused() {
        let err = workspace_load(vec![0xde, 0xad, 0xbe, 0xef]).unwrap_err();
        assert!(err.contains("malformed"), "unexpected error: {err}");
    }

    #[test]
    fn unknown_handle_is_an_error_not_a_panic() {
        assert!(file_text(999_999, FILE.into()).is_err());
        assert!(workspace_encode(999_999).is_err());
    }

    #[test]
    fn upsert_is_idempotent_and_keeps_content() {
        let ws = workspace_with_file("kept");
        file_upsert(
            ws,
            FILE.into(),
            "Characters/Renamed.md".into(),
            true,
            vec!["haoyu".into(), "horido".into()],
        )
        .unwrap();

        assert_eq!(file_text(ws, FILE.into()).unwrap(), "kept");
        let meta = file_meta(ws, FILE.into()).unwrap();
        assert_eq!(meta.path, "Characters/Renamed.md");
        assert!(meta.protected);
        assert_eq!(meta.owners.len(), 2);
        assert_eq!(file_ids(ws).unwrap(), vec![FILE.to_string()]);
    }

    #[test]
    fn apply_reports_a_file_created_by_a_peer() {
        // A change *inside* a file arrives with the file id at the front of the
        // event path; a file being created arrives as a change to the `files`
        // map itself, with an empty path. Both must be reported, or a
        // collaborator's new document syncs invisibly and never reaches disk.
        let author = workspace_create("awayside".into());
        let peer = workspace_load(workspace_encode(author).unwrap()).unwrap();

        file_upsert(
            author,
            FILE.into(),
            "Characters/Aldric.md".into(),
            false,
            vec!["haoyu".into()],
        )
        .unwrap();
        file_set_text(author, FILE.into(), "The moor is wide.".into()).unwrap();

        let update = workspace_diff(author, workspace_state_vector(peer).unwrap()).unwrap();
        let touched = workspace_apply(peer, update).unwrap();

        assert_eq!(touched, vec![FILE.to_string()]);
        assert_eq!(file_text(peer, FILE.into()).unwrap(), "The moor is wide.");

        workspace_close(author);
        workspace_close(peer);
    }

    #[test]
    fn apply_reports_a_file_removed_by_a_peer() {
        let author = workspace_with_file("The moor is wide.");
        let peer = workspace_load(workspace_encode(author).unwrap()).unwrap();

        file_remove(author, FILE.into()).unwrap();
        let update = workspace_diff(author, workspace_state_vector(peer).unwrap()).unwrap();

        assert_eq!(workspace_apply(peer, update).unwrap(), vec![FILE.to_string()]);
        assert!(file_ids(peer).unwrap().is_empty());

        workspace_close(author);
        workspace_close(peer);
    }

    #[test]
    fn applying_the_same_update_twice_reports_nothing_the_second_time() {
        // Broadcast and the durable log deliver the same bytes on purpose.
        let author = workspace_with_file("The moor is wide.");
        let peer = workspace_load(workspace_encode(author).unwrap()).unwrap();

        file_set_text(author, FILE.into(), "The moor is wide and cold.".into()).unwrap();
        let update = workspace_diff(author, workspace_state_vector(peer).unwrap()).unwrap();

        assert_eq!(
            workspace_apply(peer, update.clone()).unwrap(),
            vec![FILE.to_string()]
        );
        assert!(workspace_apply(peer, update).unwrap().is_empty());
        assert_eq!(
            file_text(peer, FILE.into()).unwrap(),
            "The moor is wide and cold."
        );

        workspace_close(author);
        workspace_close(peer);
    }


    #[test]
    fn a_cursor_follows_text_inserted_before_it() {
        // The whole point of a relative position: an absolute index is
        // meaningless to a collaborator whose copy has moved on.
        let ws = workspace_with_file("The moor is wide.");
        let at_moor = text_relative_position(ws, FILE.into(), 4).unwrap();
        assert_eq!(
            text_absolute_index(ws, FILE.into(), at_moor.clone()).unwrap(),
            Some(4)
        );

        file_set_text(ws, FILE.into(), "Beyond, the moor is wide.".into()).unwrap();
        assert_eq!(
            text_absolute_index(ws, FILE.into(), at_moor).unwrap(),
            Some(12)
        );
        workspace_close(ws);
    }

    #[test]
    fn a_cursor_in_deleted_text_collapses_rather_than_vanishing() {
        // `yrs` resolves an anchor in deleted text to where that text used to
        // be. Better for drawing a caret than losing it — but it makes the
        // result a hint, so callers must clamp it against their own length.
        let ws = workspace_with_file("The moor is wide.");
        let inside = text_relative_position(ws, FILE.into(), 6).unwrap();
        file_set_text(ws, FILE.into(), "Gone.".into()).unwrap();

        let resolved = text_absolute_index(ws, FILE.into(), inside).unwrap();
        let length = file_text(ws, FILE.into()).unwrap().encode_utf16().count() as u32;
        assert!(resolved.is_some());
        assert!(resolved.unwrap() <= length, "must be clampable, got {resolved:?}");
        workspace_close(ws);
    }

    #[test]
    fn a_cursor_survives_the_trip_between_two_peers() {
        let author = workspace_with_file("The moor is wide.");
        let peer = workspace_load(workspace_encode(author).unwrap()).unwrap();
        let position = text_relative_position(author, FILE.into(), 8).unwrap();
        assert_eq!(
            text_absolute_index(peer, FILE.into(), position).unwrap(),
            Some(8)
        );
        workspace_close(author);
        workspace_close(peer);
    }

    #[test]
    fn cursor_offsets_are_utf16_like_every_other_offset() {
        let ws = workspace_create("awayside".into());
        file_upsert(ws, FILE.into(), "Oetes.md".into(), false, vec![]).unwrap();
        file_set_text(ws, FILE.into(), "Ωετες lies east".into()).unwrap();
        // Index 5 is just past the Greek word in UTF-16 units.
        let position = text_relative_position(ws, FILE.into(), 5).unwrap();
        assert_eq!(
            text_absolute_index(ws, FILE.into(), position).unwrap(),
            Some(5)
        );
        workspace_close(ws);
    }

    #[test]
    fn a_malformed_position_is_an_error_and_an_empty_one_is_not() {
        let ws = workspace_with_file("The moor is wide.");
        assert!(text_absolute_index(ws, FILE.into(), vec![9, 9, 9, 9]).is_err());
        assert_eq!(text_absolute_index(ws, FILE.into(), vec![]).unwrap(), None);
        assert!(text_relative_position(ws, "no-such-file".into(), 0).is_err());
        workspace_close(ws);
    }

}
