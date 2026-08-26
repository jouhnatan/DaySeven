# Handoff: CRDT collaboration, session 2

You are picking up a rewrite in progress. Read this file completely before
touching anything, then read `AGENTS.md` and `README.md`.

**Scope discipline matters here.** The full rewrite is ten phases; this session
covers two of them plus build integration. Do the work in this file, verify it,
and stop. Do not start the networking phases — they are listed at the bottom
only so you understand where this is heading.

---

## 1. Where things stand

`main` is at commit `422a927`, "Add the CRDT core: yrs behind
flutter_rust_bridge". That commit is **additive and inert**: it added a working
CRDT core but wired it into nothing. Every existing code path still runs on
Supabase exactly as before, and all 22 files that import `supabase` are
untouched.

What already works and is committed:

- `rust/` — the `dayseven_crdt` crate wrapping `yrs` (Rust port of Yjs).
  **8 passing Rust tests.**
- `lib/shared/crdt/generated/` — flutter_rust_bridge bindings (generated; never
  hand-edit).
- `test/shared/crdt/workspace_crdt_test.dart` — **7 passing Dart tests** calling
  real `yrs` across the bridge.
- `flutter_rust_bridge.yaml` — codegen config.
- `rust/target/` is gitignored (874 MB — never commit it).

Baseline: `flutter analyze` clean, `./scripts/check_layers.sh` passes,
**456/457** tests pass.

> **Known pre-existing flake, not yours:**
> `test/features/search/search_bar_test.dart: opens a document when its search
> result is clicked` fails intermittently under the full suite and passes in
> isolation. It predates this work. Do not "fix" it, and do not treat it as a
> regression. If it fails, re-run it alone to confirm.

## 2. Environment

Rust is installed but **deliberately not on your PATH** — the install used
`--no-modify-path` because `~/.zshenv` already has two broken `source` lines
(`.rokit/env`, `.aftman/env`). Those errors print on every shell command and are
**harmless noise**; ignore them, do not fix them.

Prefix Rust work with:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

Installed: `rustc`/`cargo` 1.98.0, `rustfmt`, `cargo-expand`,
`flutter_rust_bridge_codegen` 2.13.0. Flutter 3.47.1.

## 3. The existing CRDT API

Do not redesign this. Dart signatures, from
`lib/shared/crdt/generated/api/workspace.dart`:

```dart
Future<BigInt>     workspaceCreate({required String workspaceId});
Future<BigInt>     workspaceLoad({required List<int> bytes});
Future<void>       workspaceClose({required BigInt handle});
Future<String>     workspaceId({required BigInt handle});
Future<Uint8List>  workspaceEncode({required BigInt handle});
Future<Uint8List>  workspaceStateVector({required BigInt handle});
Future<Uint8List>  workspaceDiff({required BigInt handle, required List<int> sinceStateVector});
Future<List<String>> workspaceApply({required BigInt handle, required List<int> update});
Future<List<String>> workspaceStageApply({required BigInt handle, required List<int> update});
Future<List<String>> fileIds({required BigInt handle});
Future<void>       fileUpsert({required BigInt handle, required String fileId,
                               required String path, required bool protected,
                               required List<String> owners});
Future<void>       fileRemove({required BigInt handle, required String fileId});
Future<String>     fileText({required BigInt handle, required String fileId});
Future<FileMeta>   fileMeta({required BigInt handle, required String fileId});
Future<void>       fileSetText({required BigInt handle, required String fileId, required String next});
```

`class FileMeta { String fileId; String path; bool protected; List<String> owners; }`

Documents live in a Rust-side registry behind integer handles, so `BigInt` is
just an opaque token. **Always `workspaceClose` what you open** or you leak.

Document shape:

```
files: Y.Map<fileId, Y.Map{ path: String, protected: bool,
                            owners: Y.Array<String>, content: Y.Text }>
workspaceMeta: Y.Map{ workspaceId, schemaVersion }
```

If you change any `pub fn` in `rust/src/api/`, regenerate:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
flutter_rust_bridge_codegen generate
```

## 4. Gotchas already paid for — do not rediscover these

1. **`OffsetKind::Utf16` is mandatory.** `yrs` defaults to `Bytes` (UTF-8), but
   Yjs indexes UTF-16. On the default, offsets disagree with Dart strings the
   moment text is non-ASCII (the KB contains `Oetes [Ωετες].md`) and updates
   stop being Yjs-compatible. All `Doc`s are built in `new_doc()` in
   `rust/src/api/workspace.rs`. **Never construct a `Doc` anywhere else.**
2. **Never replace a whole `Y.Text`.** `file_set_text` preserves the common
   prefix/suffix and rewrites only the differing span. A wholesale replace
   destroys concurrent edits and every collaborator's cursor. There is a test
   for this; keep it passing.
3. **Errors cross as `String`, not `AnyhowException`.** The Rust API returns
   `Result<T, String>`. Assert on message content in tests.
4. **`flutter_rust_bridge_codegen generate` injects `mod frb_generated;` at the
   very top of `rust/src/lib.rs`**, above the `//!` module docs, which is
   invalid Rust. After every regeneration, move that line below the doc comment
   or the crate will not compile.
5. `yrs` value type is `Out` (`Out::Any(Any::String(..))` etc.), not castable to
   `Any` directly. Helpers `as_string` / `as_bool` / `as_i64` exist.

## 5. Repo rules you must not break

From `AGENTS.md` and `scripts/check_layers.sh`:

- `shared/` may not import `app/` or `features/`. No feature may import another
  feature. Feature UI may not import `app/shell/`.
- Rendered `fontSize:` must come from `uiTextStyle` or `editorTextStyle`.
- **Do not bump `version:` in `pubspec.yaml`. Do not tag. Do not publish a
  release.** `AGENTS.md` says to ship completed changes by default — that rule
  is **suspended for this session**, because the work here is inert scaffolding
  mid-rewrite and shipping it would deliver nothing while risking the updater
  for the two people who run this app.
- Do not touch `supabase/migrations/`, the release feed, or
  `lib/shared/platform/app_update.dart`.

> **Supabase is not going away — be clear on this before you design anything.**
> The finished architecture keeps it in **two** roles:
>
> 1. **Collaboration transport.** Yjs updates ride Supabase Realtime Broadcast
>    on a new client-writable `crdt:<kbId>` topic; Awareness rides the existing
>    `presence:<kbId>` topic; and durable CRDT state lives in Postgres
>    (`yjs_updates` / `yjs_snapshots`) so a peer that was offline catches up.
>    This is **not** peer-to-peer and there is no embedded server.
> 2. **Build updates.** `app_releases` and the `releases` bucket, unchanged.
>
> Both roles are out of scope for *this session* — the steps below are
> deliberately offline so they can be tested without a backend. That is a
> property of this slice, not of the system. Do not design the workspace store
> as though sync will be local-only or peer-to-peer; it will be a relay, and the
> store must be able to hand out and apply incremental updates
> (`workspaceDiff` / `workspaceApply`) rather than only whole documents.
- Never print, commit or echo `SUPABASE_SERVICE_ROLE_KEY`.

---

## 6. The work

### Step 1 — Bundle the native library into the app build

Right now the dylib is only reachable from tests via an explicit path. The real
app cannot load it. Until this is done, nothing downstream can ship.

Use the supported path for an existing project:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
flutter_rust_bridge_codegen integrate
```

This installs Cargokit, which hooks `cargo build` into CocoaPods (macOS) and
CMake (Windows) so the library is built and bundled automatically.

Then:

- Replace the explicit-path `RustLib.init(externalLibrary: ...)` in
  `test/shared/crdt/workspace_crdt_test.dart` with the default `RustLib.init()`
  **only if** integration makes that work under `flutter test`. If it does not,
  keep the path-based loader for tests — it is not worth fighting.
- Initialise `RustLib.init()` once at startup in `lib/main.dart`, beside the
  existing `Supabase.initialize`. It must not throw if the library is missing;
  degrade to "collaboration unavailable" the way missing Supabase credentials
  already degrade to local-only.
- Add the Rust toolchain to **both** `.github/workflows/macos-release.yml` and
  `.github/workflows/windows-release.yml` (e.g. `dtolnay/rust-toolchain@stable`)
  before the `flutter build` step.

**Verify:** `flutter build macos --debug` succeeds and the app launches.
Confirm the dylib is inside the built `.app` bundle.

> **Windows is unverified and is the main risk in this whole project.** It
> cannot be tested from this machine. If you cannot verify it, say so plainly in
> your final report rather than implying it works. A release that builds on one
> platform and not the other splits the two users across incompatible versions.

### Step 2 — Workspace loading (plan Phase 2)

New file: `lib/shared/crdt/workspace_store.dart` (in `shared/`, so it may not
import `app/` or `features/`).

On opening a Knowledge Base:

1. Create `<kb-root>/metadata/yjs/` if missing.
2. Load and validate `workspace.bin` if present. On a schema version this build
   does not understand, refuse and surface a clear message — never partially
   apply.
3. Recursively scan for `.md` files, **ignoring `metadata/`** and `.settings/`.
4. Match known files by normalised path; assign UUIDs to new ones.
5. Import new Markdown content into `Y.Text` via `fileSetText`.

Reuse `lib/shared/kb/bundle.dart` for path resolution — do not reimplement it.

**File ids:** reuse the existing `BlockDocument.id`. Do not mint a second
identity. (These already match the `documents.id` column exactly — verified
against live data, zero mismatches.)

**Note the directory conflict, and follow the spec anyway:** DaySeven keeps its
own state in the hidden `.settings/`, and this adds a *visible* `metadata/`.
That inconsistency is intentional and accepted; do not "tidy" it by renaming
either one.

### Step 3 — Persistence (plan Phase 3)

- Debounce writes (~600 ms; match `open_document.dart:45`).
- Write `workspace.bin.tmp`, **flush**, then atomically rename to
  `workspace.bin`. Never write the real file directly.
- Enforce a configurable maximum workspace size.
- A crash mid-write must leave the previous good file intact.

### Step 4 — Markdown materialisation and external edits (plan Phase 4)

**Y.Text → Markdown:** write via atomic temp-file rename. Suppress
self-generated watcher events — `lib/app/workspace/kb_session.dart` already has
a 250 ms debounced watcher (`_watchDelay`, line 32) and is where suppression
belongs. Resolve every path against the KB root; **reject path traversal,
symlinks escaping the root, and non-Markdown targets.**

**Markdown → Y.Text:** call `fileSetText`, which already computes a
prefix/suffix-minimal edit in Rust. Do **not** add a second diff layer in Dart.

Watch for the write loop: materialising must not retrigger import.

### Step 5 — Hide `metadata/` (plan Phase 9, the part that matters now)

Exclude `metadata/` from the file tree, search and FTS5 indexing so it does not
appear as user content. Touches
`lib/features/knowledge_base/ui/knowledge_base_menu.dart` and the indexer in
`lib/shared/blocks/`. Never open `workspace.bin` as a document.

The developer setting ("Show workspace metadata") and the packaging/export rules
can wait.

---

## 7. Definition of done

All of these must hold:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
cd rust && cargo test          # 8+ passing
cd .. && flutter analyze       # no issues
flutter test                   # 463+ passing; only the known search flake may fail
./scripts/check_layers.sh      # passes
flutter build macos --debug    # succeeds, app launches
```

New tests required — these are the acceptance criteria, not optional extras:

- Markdown import on first open of an existing KB
- `workspace.bin` restoration across a close/reopen
- **Atomic-write recovery**: kill mid-write, previous good file survives
- External file edit applied as an incremental change, **not** a wholesale
  `Y.Text` replacement
- File rename handling
- **Path traversal and symlink-escape attempts are rejected**
- `metadata/` absent from the tree and from search results

Use the real Awayside layout as a fixture shape where practical: 9 documents,
nested folders, and at least one non-ASCII filename (`Oetes [Ωετες].md`).

**Commit** in logical units with real messages. **Do not tag or release.**

## 8. Explicitly out of scope

Do not start these. They are the next sessions:

- The `crdt:<kbId>` Realtime topic, RLS on `realtime.messages`, the Dart
  broadcast provider (Phase 5)
- `yjs_updates` / `yjs_snapshots` durability tables (Phase 5) — **note: DB
  writes must be debounced 2–5 s; per-keystroke writes through PostgREST would
  recreate the outage that started this project**
- Abuse protection, backoff, circuit breaker, timeout alignment (Phase 6)
- `policy.json`, protected-file gating, proposals (Phase 7)
- Awareness/presence migration (Phase 8)
- Removing the Supabase sync layer — **it stays working until CRDT sync is
  proven end to end.** Do not delete `lib/features/differences/` or the
  three-way merge in `lib/shared/blocks/`.

Full plan, if you need the reasoning behind any of this:
`~/.claude/plans/analyse-the-codebase-currently-zesty-firefly.md`

## 9. Report honestly

State plainly what you did, what you verified, and what you could not verify —
especially Windows. If something is half-done, say so. Do not report completion
for work you did not test.
