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

### 4.6 Policy signing, and getting the policy to the other person

Signing is **done**, along the lines decided below. `CrdtCollaborationController`
generates a per-device-user Ed25519 keypair on first need, stores the secret
through `PolicyKeyStore` (keychain, else a 0600 file), and signs
`metadata/yjs/policy.json` from the database's own view of membership and
protection. App settings → Collaboration shows signing health and offers
**Republish**, which is the repair for a fresh install or a lost key.

**Distribution was the missing half, and it is why collaboration never worked
for the second person.** `metadata/` is excluded from sharing and is not part
of the CRDT document, so a signed `policy.json` never left the machine that
signed it. Only the public key was published, which left every member who
cannot sign looking at a key, no file, and "the signed policy file is missing"
— with no action available to them, and no action on the owner's machine that
would help. The owner's own client looked healthy throughout, because its file
verified against its own key.

The signed document is now published alongside the key, atomically, through
`publish_policy` (`knowledge_bases.policy_document`, migration
`20260827012720`). A member without a local copy fetches it, verifies the
signature and the embedded `kb_id`, runs with it, and caches it to disk so the
workspace still opens offline. **The server is transport, not an authority**:
nothing published is believed unverified, so a tampered row fails exactly the
way a tampered file does. `lib/shared/crdt/policy_bootstrap.dart` holds that
decision as pure logic, which is what makes the awkward combinations testable
without two machines — see `test/shared/crdt/policy_bootstrap_test.dart`.

Key storage, decided earlier and unchanged: the keypair is generated per
device-user from OS entropy and indexed by username. Usernames are immutable
here, so they are a stable handle for a key that has to outlive password
changes.

> **The username is an index, not key material.** It identifies which stored
> key to load. It is public — presence broadcasts it, `profiles` exposes it —
> so deriving, seeding or generating the secret from it, or from any other
> public value, would let anybody who knows a username forge that person's
> policies and hand themselves ownership. Generate from OS entropy, which is
> what `policy_generate_keypair` already does. Never send the secret to the
> server and never write it to the security log.

Consequences already handled, not to rediscover: an owner on a new machine
republishes rather than silently losing the ability to sign; a lost key is
recovered by republishing a new public key, which re-signs and re-publishes
the document in the same step, so members pick the new root up on next open.

### 4.7 The cutover

Removing `lib/features/differences/` and the three-way merge in
`lib/shared/blocks/` happens only after §4.1 has been done and lived with.

### 4.8 Suggested order

Not arbitrary. Each of these makes the next one testable.

1. ~~**§4.6, policy signing.**~~ **Done**, signing and distribution both.
   Phase 7 is no longer inert.
2. ~~**§4.5, the settings toggles.**~~ **Done**: App settings → Collaboration.
3. **§4.3, link state in the UI.** Do this before §4.1, not after: without it,
   a failed sync during testing is indistinguishable from nothing happening,
   and you will not know which you are looking at.
4. **§4.1, two real machines.** The point of the whole exercise.
5. **§4.2, compaction.** Once §4.1 has produced a log worth compacting, and
   once you can see from §4.3 whether it worked.
6. **§4.4, drawing carets.** Cosmetic, and easiest to get right when sync is
   already known good.
7. **§4.7, the cutover.** Only after §4.1 has been lived with.

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
- ~~Where an owner's policy secret key lives.~~ **Decided**: generated on
  device, stored locally indexed by username. See §4.6 for the build order and
  for why the username indexes the key rather than producing it.
- **Whether `sync-step-1` should ever be answered.** It is accepted by the
  protocol and currently ignored: the durable log answers catch-up better, and
  replying would mean sending full state to anyone who asks, repeatedly.

Full plan, for reasoning behind any of this:
`~/.claude/plans/analyse-the-codebase-currently-zesty-firefly.md`

## 9. Shipping

Two different questions, and they have different answers.

**The outage fix should ship, and has not.** `RetryBudget`, the `retryCount: 0`
change and the timeout alignment are client-side, and no released build has
them. The current release is **v1.3.19+24** on both platforms, published
2026-08-26 00:26 UTC — *during* the incident. `private.publish_gate` caps a
looping client server-side, so this is no longer urgent, but until a build
ships, the bug is still on somebody's machine. This is an ordinary completed
change and `AGENTS.md` applies to it normally.

**The CRDT work delivers nothing yet, and that is fine.** It is unreachable
without `AppStore.crdtCollaboration`, which has no UI and defaults off. It
rides along in the same release because it is on the same branch; it does not
justify one on its own, and §4.1 is not a precondition for shipping the fix
above.

Before tagging, know that shipping the branch also ships, to every user,
regardless of the flag:

- `retryCount: 0` and a 10s `requestTimeout` on every PostgREST call
- publish retry budgets in `DifferencesController` and `SharingController`
- a `security.log` written in the app support directory
- an extra `AppStore` read when a Knowledge Base opens

All are intended. None depend on the CRDT flag. Sanity-check them on a real
build rather than assuming, because they are on the path everybody uses.

The Rust library already ships: v1.3.19 built and published on **both**
platforms with Cargokit and the toolchain in both workflows, which retires the
"Windows is unverified" risk the earlier handoff carried. Adding
`ed25519-dalek` is the only new native dependency since.

Follow `AGENTS.md` when you do it: bump `version:` (raise the build number),
tag to match exactly, watch both workflows, and confirm the feed moved.
