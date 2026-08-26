# Handoff: CRDT collaboration

You are picking up a rewrite that is **built but not proven**. Read this file
completely before touching anything, then read `AGENTS.md` and `README.md`.

Phases 1–10 of the plan are implemented and committed. **None of it has ever
run between two real machines.** That is the whole of what is left, and it is
not a formality — see §4.

---

## 1. Where things stand

Ten phases, all landed:

| Phase | What it is | Where |
|---|---|---|
| 1–4 | yrs core, workspace loading, persistence, Markdown materialisation | `rust/`, `lib/shared/crdt/workspace_store.dart` |
| 5 | Durable log, `crdt:<kbId>` topic, chunked protocol | `lib/shared/crdt/crdt_{sync_repository,protocol,session}.dart` |
| 6 | Limits, backpressure, jittered backoff, timeout alignment | `crdt_session.dart`, `lib/shared/backend/retry_budget.dart` |
| 7 | Signed policy, receive-side gate, proposals | `workspace_policy.dart`, `crdt_authorization.dart` |
| 8 | Awareness cursors as Yjs relative positions | `awareness.dart`, `lib/shared/presence/peer_presence.dart` |
| 9 | `metadata/` hidden, developer setting to show it | `lib/shared/kb/bundle.dart`, `lib/app/app_store.dart` |
| 10 | Security log | `lib/shared/security/security_log.dart`, `lib/app/security_log.dart` |

Baseline, all verified on 2026-08-26:

```bash
export PATH="$HOME/.cargo/bin:$PATH"
cd rust && cargo test          # 22 passing
cd .. && flutter analyze       # clean
flutter test                   # 608 passing
./scripts/check_layers.sh      # passes
flutter build macos --debug    # succeeds; app launches, dylib bundled
```

> **Known pre-existing flake, not yours:**
> `test/features/search/search_bar_test.dart: opens a document when its search
> result is clicked` fails intermittently under the full suite and passes in
> isolation. It predates all of this. Do not "fix" it. Re-run it alone to
> confirm.

## 2. Environment

Rust is installed but **deliberately not on your PATH** — the install used
`--no-modify-path` because `~/.zshenv` has two broken `source` lines
(`.rokit/env`, `.aftman/env`). Those errors print on every shell command and
are **harmless noise**; ignore them, do not fix them.

```bash
export PATH="$HOME/.cargo/bin:$PATH"
```

Installed: `rustc`/`cargo` 1.98.0, `flutter_rust_bridge_codegen` 2.13.0,
Flutter 3.47.1. `rust/target/` is gitignored (874 MB — never commit it).

If you change any `pub fn` in `rust/src/api/`, regenerate:

```bash
flutter_rust_bridge_codegen generate
```

## 3. How it fits together

```
KbController opens a Knowledge Base
  └─ CrdtCollaborationController          lib/app/workspace/crdt_collaboration.dart
       ├─ WorkspaceStore                  the yrs document, behind the Rust bridge
       ├─ WorkspacePolicy (verified)      metadata/yjs/policy.json + key from Postgres
       ├─ CrdtAuthorizationGate           stage → judge → apply
       └─ CrdtSession                     transport
            ├─ CrdtSyncRepository         yjs_updates / yjs_snapshots / yjs_proposals
            ├─ CrdtAssembler              chunking, replay rejection, size limits
            └─ SecurityLog                what was refused, and why
```

Outbound: local edit → diff since last send → broadcast (200 ms) **and** push
to the log (3 s). Inbound: frame → assemble → bounded queue → stage → judge →
apply → materialise to Markdown.

**Off by default.** `AppStore.crdtCollaboration` must be switched on. Until
CRDT sync is proven, `documents`/`revisions` and the reviewed-edit workflow in
`lib/features/differences/` stay authoritative and must not be deleted.

## 4. What is actually left

### 4.1 Prove it between two machines — the only real task

Everything is tested against a `FakeRelay`, a fake channel, and direct SQL.
Two real clients have never synced. Until they have, treat all of the below as
unverified:

- Two signed-in clients on one Knowledge Base, `crdtCollaboration` on.
- One types; the other sees it. Check the broadcast path and the log path
  separately — kill the socket on one client and confirm it catches up from
  `yjs_updates` on reconnect.
- A first sync of the real Awayside KB (9 documents, nested folders,
  `Oetes [Ωετες].md`). **This is where chunking gets its first real test**;
  everything above 256 KB has only ever been exercised synthetically.
- A protected file: confirm an editor's change becomes a proposal, an owner
  can approve it, and the approved bytes reach both documents.
- Watch `select count(*) from public.yjs_updates` while somebody types for a
  minute. If it grows faster than about one row every three seconds, the
  debounce is not working and you should stop and fix that before anything
  else.

### 4.2 Compaction is never called

`yjs_compact` exists, is tested, and enforces its own ordering. Nothing
decides when to run it, so the log grows forever. Owners and co-owners only.
A reasonable trigger is on Knowledge Base close when the log is over some
length, but this is a real decision, not a detail.

### 4.3 Nothing shows collaboration state in the UI

`CrdtSession.states` and `.refusals` are streams nobody watches.
`CrdtLinkState` carries health, cursor, pending-push and queue depth. A
refused update currently tells the person nothing.

### 4.4 Nothing draws collaborators' carets

`AwarenessResolver` resolves peers to clamped offsets and is tested, and
presence sends the anchors. No editor code renders them.

### 4.5 No UI for the developer settings

`AppStore.showWorkspaceMetadata` and `AppStore.crdtCollaboration` are read at
Knowledge Base open but can only be set by editing the JSON in the app support
directory. App settings needs toggles — and note `AGENTS.md`: App settings
follows its own design deliberately, so match what is there.

### 4.6 No one has ever signed a policy

`WorkspacePolicy.signedJson` and `set_policy_public_key` work and are tested,
but no code path generates an owner keypair, writes `policy.json`, or
publishes the key. **Where the owner's secret key is stored is an open
decision** — it must never reach the server, and it is currently nowhere.
Until this exists, every Knowledge Base runs with `policy: null`, which means
nothing is protected on the CRDT path and only the server's own checks apply.

### 4.7 The cutover

Removing `lib/features/differences/` and the three-way merge in
`lib/shared/blocks/` happens only after §4.1 has been done and lived with.

## 5. Gotchas already paid for — do not rediscover these

1. **`OffsetKind::Utf16` is mandatory.** `yrs` defaults to `Bytes` (UTF-8), but
   Yjs indexes UTF-16. All `Doc`s are built in `new_doc()` in
   `rust/src/api/workspace.rs`. **Never construct a `Doc` anywhere else.**
2. **Never replace a whole `Y.Text`.** `file_set_text` preserves the common
   prefix/suffix. A wholesale replace destroys concurrent edits and every
   collaborator's cursor. There is a test; keep it passing.
3. **The first update a peer sends must be the whole document, not a diff.** A
   diff is relative to a state vector, and the only one a peer can name is its
   own — which omits its own earlier operations, leaving every later update
   causally dangling and permanently unapplied, silently, because Yjs buffers
   rather than errors.
4. **An empty Yjs v1 update is `[0, 0]`, not zero bytes.** Use
   `isEmptyYjsUpdate`. Without it an idle workspace appends a row per debounce
   tick forever. The server rejects them too.
5. **`workspace_apply` reports created files via the event's *keys*, not its
   path.** A change inside a file has the file id at the front of the event
   path; a file being created is a change to the `files` map itself, with an
   empty path. Missing the second case means a collaborator's new document
   syncs invisibly and never reaches disk.
6. **A relative position resolves to a *hint*.** An anchor in deleted text
   resolves to where that text used to be, not to nothing. Clamp against the
   local length — `AwarenessResolver` does.
7. **Never open a second transaction inside a `with_doc` read.** It deadlocks.
   `text_relative_position` needs a mutable transaction, so it opens exactly
   one.
8. **Errors cross the bridge as `String`.** Assert on message content.
9. **`flutter_rust_bridge_codegen generate` can inject `mod frb_generated;`
   above the `//!` module docs in `rust/src/lib.rs`**, which is invalid Rust.
   Check after every regeneration.
10. **Block ids are not prefix-free.** `markdownBodyOffsetOfBlock` matches
    `<!-- d7 <id> ` *with* the trailing space, or `p-1` finds `p-10`.

## 6. Repo rules you must not break

- `shared/` may not import `app/` or `features/`. No feature may import
  another feature. Feature UI may not import `app/shell/`.
- Rendered `fontSize:` must come from `uiTextStyle` or `editorTextStyle`.
- **Clients may never gain `insert` on `kb:%`.** That topic is the
  server-authored notification bus. `presence:%` and `crdt:%` are the
  client-writable ones, and a fourth client-sent message gets a fourth topic
  rather than widening one of these.
- **Every CRDT write goes through an RPC.** `yjs_updates`, `yjs_snapshots` and
  `yjs_proposals` grant `select` only — the RPCs are where the size, rate and
  role limits live, and a direct insert would skip all of them.
- **Showing `metadata/` is a view setting.** It must never widen what gets
  synced, published, or deleted. Two `readTree()` calls deliberately do not
  take the flag; comments say so.
- **The security log takes identifiers, never content.** No document text, no
  keys, no invite codes, no usernames on auth failures.
- Never print, commit or echo `SUPABASE_SERVICE_ROLE_KEY`.

## 7. The outage this replaced

On 2026-08-25 a shipped client looped on `publish_document_change`: 5,573,597
rejected calls in 24 hours, peaking near 970/second, from one user. It was
never a capacity problem — storage is 129 MB of 1 GB. It was
`DifferencesController._submitDebounced` re-entering with no delay and no
attempt limit on a working copy that had just failed.

Two guards, and **do not remove either**: `RetryBudget` client-side, and
`private.publish_gate` in the database. The CRDT path has its own equivalents
(`yjs_rate_ok`, the inbound queue bound, the push budget) for the same reason.

If you are ever tempted to add an automatic retry anywhere in this codebase:
retries belong where the caller knows whether the request can succeed at all,
they back off, they jitter, and they give up.

## 8. Open decisions, not tasks

- **End-to-end encryption.** The plan flags it as optional. It is *not*
  implemented, and implementing it would make server-side protected-file
  gating impossible — the server cannot inspect what it cannot read — leaving
  only `CrdtAuthorizationGate` client-side. Decide before building on phase 7.
- **Where an owner's policy secret key lives.** See §4.6.
- **Whether `sync-step-1` should ever be answered.** It is accepted by the
  protocol and currently ignored: the durable log answers catch-up better, and
  replying would mean sending full state to anyone who asks, repeatedly.

Full plan, for reasoning behind any of this:
`~/.claude/plans/analyse-the-codebase-currently-zesty-firefly.md`

## 9. Shipping

`AGENTS.md` says to ship completed changes by default. **That rule stays
suspended** until §4.1 is done. None of this is reachable without a developer
flag, so shipping it delivers nothing while risking the updater for the two
people who run this app. Do not bump `version:`, do not tag.
