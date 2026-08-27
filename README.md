# DaySeven

A world-building knowledge base editor for macOS and Windows 11.

Your content is a **Knowledge Base**: an ordinary folder, in a location you
choose, holding a folder-and-file tree of documents. Your folders sit directly
in it — a `Characters/` folder is just `Characters/`. The app keeps its own
files in `.settings/`, out of the way. Nothing is encoded: the manifest is
readable JSON, the documents are files, and `.settings/.index/` is derived and
safe to delete.

Collaboration is **reviewed**, not simultaneous. A collaborator's edit becomes a
pending proposal; you see it as a split diff and decide. Nothing touches your
file until you approve it.

## Running it

```bash
cp env/supabase.example.json env/supabase.json   # fill in your project's values
flutter run -d macos --dart-define-from-file=env/supabase.json
```

Supabase credentials are optional. Without them the app runs entirely locally: a
Knowledge Base is a folder, and only collaboration needs the network.

## Layout

```
lib/
  main.dart      Boots Supabase and runs the app
  app/           The composition root — the one place features meet
    app.dart       MaterialApp and the first-run install check
    view.dart      Which workspace view is selected
    app_store.dart Per-installation state: recents, pane widths
    shell/         The three-pane frame and resizable pane state
    workspace/     What is currently open: the Knowledge Base, the document,
                   the sharing that syncs them, and who else is here
  features/      One folder per feature: ui/, plus state/, data/ or domain/
    auth/          The sign-in button
    editor/        The document editor and its rich-text controller
    home/          The landing screen
    knowledge_base/The right-side menu, dialogs, and KB repository
    differences/   Review queue, previews, merge, proposals and Realtime state
    search/        Query state and the search bar
    views/         The left-side Home and Editor navigation menu
  shared/        Used by more than one feature; depends on no feature
    blocks/        Block model, revisions, the FTS5 search index — pure Dart
    presence/      Where a collaborator is — pure Dart, and ephemeral
    kb/            Knowledge Base bundle: the folder on disk
    documents/     ODT and DOCX import/export
    auth/          Who is signed in
    backend/       Supabase client, error vocabulary, document repository
    platform/      Install-location check
    ui/            The palette and type scale, controls, menus, dialogs
supabase/
  migrations/    Schema, RLS, RPCs, Realtime trigger, Storage bucket
scripts/         Packaging and publishing for macOS (DMG) and Windows (zip)
```

### Where new code goes

Three rules, checked by `scripts/check_layers.sh`:

- **`shared/` imports nothing from `app/` or `features/`.** It is the bottom of
  the stack. Something belongs here once a second feature needs it — not in
  anticipation of one.
- **No feature imports another feature.** If two features need to talk, the
  thing they are talking about is usually neither one's: it goes in `shared/`
  if it is a model or a helper, or in `app/` if it coordinates them.
- **Feature UI does not import `app/shell/`.** A control used by the shell and
  a feature belongs in `shared/ui/`; the shell is a consumer, not a widget kit.
- **`app/` may import anything.** It composes the features into an application,
  so it is allowed to know about all of them.

`app/workspace/` holds the open Knowledge Base and the open document. They live
there rather than in a feature because nearly every feature reads them: the
editor edits the open document, but search, Differences, home and the KB menu all
read it too.

Application-wide preferences live together in
`shared/ui/global_settings.dart`. Add future global settings to `DsAppSettings`
so the composition root can rebuild the whole app from one listenable value.
Text in controls, menus, navigation and other application chrome must use
`uiTextStyle`; document titles, prose, headings, tables, captions and code must
use `editorTextStyle`. Their sizes scale from the independent UI and editor base
sizes in the global settings rather than from feature-local constants.

## How it looks

The interface follows **Cream & Fern**, written out in full in
[`docs/design-system.md`](docs/design-system.md). That document is the source of
truth; what follows is only what an agent needs to know before touching a widget.

The ground is warm cream, never white. Structure is drawn with hairlines rather
than filled bars. There is exactly one saturated colour — a deep fern green —
and it is spent at most twice per view, on the two things that matter: **where
you are**, and **the action that commits**. Solway labels regions; Instrument
Sans carries every word the user actually reads. There is no monospace: numbers
that line up use tabular figures in the same sans.

Three things follow from that, and `scripts/check_layers.sh` enforces the first
two:

- **Colour comes from `shared/ui/theme.dart`.** `CF` states the palette and
  `DsColors` names the roles the interface reads through, as `context.ds`. A
  literal `Color(0x…)` or `Colors.…` anywhere else in `lib/` fails the check.
- **Size comes from `uiTextStyle` or `editorTextStyle`,** as it always has.
- **Depth comes from borders, not shadows.** Panes, cards and tiles are flat
  with a 1px edge. Only a menu, a popover or a dialog — things genuinely above
  the page — carries a shadow.

There is one palette. The system is light and has no dark variant, and one must
not be added; a dark title bar, sidebar or footer is not something this
interface has. Fern is allowed to be the only dark mass on screen.

The one deliberate departure is the **gradient background** on Home, which the
system otherwise forbids. It is kept because it is wanted, and kept quiet so it
reads as atmosphere: it stands on the same recessed cream as everything else and
draws only in colours the palette already contains.

## How a document is stored

Each document is a Markdown file — one block per paragraph, with stable block
ids:

```
MyWorld/
  Characters/
    Aldric.md
  Places/
    Aldenmoor.md
  .settings/           the app's own files, hidden from the tree
    dayseven.kb.json   manifest: kbId, name, schemaVersion
    assets/            images referenced by documents
    .index/            search index (derived; safe to delete)
```

Headings, paragraphs, lists (bulleted, numbered, nested and task), quotes,
fenced code, tables, footnotes, links, horizontal rules and images — bundled or
by URL. A document opens in any editor:

```markdown
---
d7: 1
schema: 1
id: "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1"
title: "Aldenmoor"
---

<!-- d7 h1 -->
## The Fen

<!-- d7 p1 -->
The moor is **wide** and <u>cold</u>.

<!-- d7 p2 align=center space=16 -->
<span style="color:#8A3B12">Aldenmoor</span>, the last free hold.[^1]

<!-- d7 l1 -->
- reeds
<!-- d7 l2 -->
  - [x] standing water

<!-- d7 t1 -->
| Place | Holder |
| --- | ---: |
| Aldenmoor | Aldric |

<!-- d7 f1 -->
[^1]: Or so the ledger says.
```

Two things Markdown has no syntax for are handled differently, and the split is
deliberate. **Inline** formatting — underline, colour, highlight, font — becomes
inline HTML, which renders correctly in other editors. **Block-level**
attributes — alignment, space before — go in the `d7` comment rather than a
`<p align>` wrapper, because CommonMark does not parse Markdown inside an HTML
block: wrapping a paragraph would render its bold and italics as literal
asterisks everywhere else.

The `d7` comment also carries the block id, which is what lets the three-way
merge tell a paragraph that *moved* from one deleted and another inserted.
Editing a document elsewhere is fine; deleting those comments only costs the
merge that knowledge, and fresh ids are minted on the next read.

Knowledge Bases written by an earlier version hold `.d7doc` JSON files. They are
converted on open — but only once the converted file has been read back and
compared against the original, and the `.d7doc` is then kept as a `.bak` rather
than deleted. Anything that fails that check is left exactly as it was and goes
on working in the old format.

Creating a Knowledge Base scaffolds nothing but `.settings/` — the structure is
yours to make. A Knowledge Base from an earlier layout migrates the first time
it is opened, by renaming rather than copying.

The same JSON is what goes into `revisions.content` in Postgres and what the
diff view compares, so a document has one shape everywhere.

`.odt` and `.docx` are import and export formats, not the storage format.

## Reviewed collaboration

| Step | What happens |
|---|---|
| An Editor or Co-Owner saves | Their local file is written immediately; a separate network debounce upserts their pending `change_set` against the sync-ledger base |
| They keep editing | The same author/document proposal is updated; another collaborator gets a separate proposal card |
| Realtime fires | A private channel carries only wake-up metadata — never proposal content — and the client refreshes from Postgres |
| You open *Views → Differences* | The complete pending queue appears as read-only document paper previews with `@username` bands |
| You choose toolbar *Differences* | Only proposals for the open document are offered; one proposal opens directly |
| **Approve** | A three-way merge runs, then one server-side transaction writes the new revision; only then is your file rewritten |
| **Reject** | The proposal is marked rejected. No revision is written, your file is untouched |
| **Return** | The diff closes and the proposal stays pending |

Editors always use reviewed submission. Co-Owners use reviewed submission by
default, while Owners and Co-Owners have an explicit *Publish directly* action
that is protected by optimistic revision locking. Reviewers can inspect and
resolve proposals but cannot edit the Knowledge Base working copy.

The merge aligns paragraphs by their stable ids and merges *within* a paragraph
at character level, with formatting attached to the characters it applies to.
That is what lets one person bold a phrase while another rewrites a different
sentence and keep both. Where the two genuinely overlap, the proposal wins and
the block is marked as conflicted in the diff before you approve.

## Live presence

Editing is reviewed, but *being there* is live. While a Knowledge Base is
shared, each person broadcasts where they are, and you see them in three
places:

- a coloured initial on their document's row in the Knowledge Base tree,
- a marker out in the page margin beside the block their caret is in, when you
  have that document open too,
- and a dot beside the save state in the bottom bar, for anyone in the open
  document.

There are no line numbers to point at. A document is a list of blocks with
stable ids, so a position is a block, which is the better address anyway: a
block id survives the other person editing above it, and it survives your two
copies holding different text while a proposal waits for review. A character
offset would survive neither.

That last case is why the bottom-bar dot exists. Until you approve their
proposal, a collaborator can be sitting in a block your copy does not have. No
marker can honestly be drawn against any of your blocks, so none is — but they
are still in the document, and the bottom bar says so.

Presence is **ephemeral and content-free**. Realtime holds it per connection
and drops it when the socket closes; nothing is written to a table, no revision
is created, and the sync ledger is untouched. The payload is a user, a path, a
document id and a block id — the same identifiers-only rule the notification
bus follows. If the presence channel fails entirely, the app behaves exactly as
it did before it existed, and nothing about it is ever shown as an error.

It is on whenever you are signed in to a shared Knowledge Base, and off
entirely otherwise: signed out, without Supabase configured, or in a folder
that is yours alone, nothing is broadcast. Somebody who has been invited but
has not accepted neither sees nor is seen. After five minutes untouched a
person's dot goes hollow, so a laptop left open stops claiming they are at the
desk.

### Its own channel, deliberately

Presence is the one thing clients *send*, so its topic — `presence:<kbId>` — is
the one granted `insert` on `realtime.messages`. The notification bus,
`kb:<kbId>`, stays read-only for clients: everything published there comes from
a database trigger, and a client able to insert into it could forge a
`document_published` event and drive a collaborator's sync. Splitting the topic
is what keeps the write grant away from the bus that is trusted to be
server-authored.

## Interface

- **Three panes** — the Views menu, the editor and the Knowledge Base menu
  are rounded panes on the application background, each a subtle tone apart.
- **Left** — a Solway heading, *Views*, above a rounded island containing
  Home, Editor and Differences. Differences carries the durable pending count.
  Beneath it a second heading, *Notifications*, sits above an island listing
  the latest five events — publishes, sync results, sharing, errors — newest
  first. A new notification fades in while the rest slide down one notch; each
  row shows its event's icon and how long ago it happened (0–60m, 1–24h,
  1d+). Every row leads with the generic action ("Document Published") and a
  hairline separates neighbouring rows; tapping a row lerps the more specific
  subtext open beneath the header.
- **Top** — a persistent search bar over the Knowledge Base's local FTS5 index,
  matching as you type.
- **Right** — a Solway *Knowledge Base* heading, a rounded control naming
  the open folder, a manual Sync button that pulls before publishing or
  proposing local changes, a gear that opens Settings on the Knowledge
  Base section, and a separate hierarchy island beneath it. The
  tree shows folder and document icons, and a hairline running down from each
  folder that turns in to meet its children. The selected row is a solid fern
  block — in a tree, that block is the interface saying where you are. A plus button at the right of
  every editable folder creates and opens an Untitled document inside it. Drag
  a document or folder onto another folder to move it, or onto the panel
  background to bring it back out to the top level; the file is renamed on
  disk, not copied.
  Right-click a document to rename it, or edit its title in the editor and
  press Enter or click away; the Markdown filename is the canonical title
  everywhere. Right-click any item to delete it after a permanent-deletion
  confirmation. A collaborator viewing a document shows as a coloured
  initial on its row.
- **Resizing** — drag the gap between the three panes. The editor keeps a
  minimum width however far you drag, and the widths are remembered between
  sessions.
- **Bottom** — an editor-width toolbar island with extra vertical breathing
  room. Formatting controls stay as individual buttons; an ellipsis menu holds
  the open-document *Differences* shortcut. The reviewed-edit save state and
  explicit publish and protection controls remain visible beside it, and
  beside that, anyone else in the open document.
- **Top right** — one rounded button: "Sign in" when signed out, your display
  name when signed in, opening a short menu to change that name or sign out.
- **Home** — "Welcome back!" in Archivo, and recent files.

Accounts are **username and password**. The username is what a collaborator
invites you by and what appears on proposal paper bands. Sharing a
Knowledge Base and inviting someone to it sit in the Knowledge Base dropdown,
since they belong to the Knowledge Base rather than to the account.

Formatting comes from the toolbar in the bottom bar — headings, bold, italic,
strikethrough, underline, the three alignments, a horizontal-rule button and
image insertion — from keyboard shortcuts (⌘/Ctrl+B, I, U, ⇧⌘X), and from a
context menu on a block for the rest: colour, highlight, font, spacing, block
kind, images, tables, footnotes and export.

Hovering a block in the editor reveals a small ellipsis at its right edge; it
opens the same context menu, whose delete entry removes that block and
everything in it — including images, caption and all. Image captions are an
ordinary field under the picture: type and it saves with the caret where you
left it.

Typing `## `, `- `, `1. ` or `> ` at the head of a paragraph turns it into that
kind of block. It fires only as the space is typed, so a pasted line stays
text.

The toolbar acts on whatever the caret is in. Its formatting buttons need a
selection, so they are muted until there is one; alignment and headings apply to
the whole block and stay available.

Documents and folders are created from the island dropdown, or by right-clicking
a folder in the tree to create inside it.

The tree follows the folder as it changes: add, rename or delete a folder in
Finder or Explorer and it appears in the panel straight away, with new documents
picked up by search.

## Platform notes

**macOS.** The app belongs in `/Applications`; running a release build from
elsewhere shows a dismissible notice and continues, and refuses to self-update.
The App Sandbox is deliberately off: DaySeven ships as a DMG rather than through
the App Store, the sandbox would make reopening a recent Knowledge Base folder
fail without security-scoped bookmarks, and replacing its own bundle needs
ordinary filesystem access.

**Windows 11.** Shipped as a zip rather than an installer: a Flutter Windows
build is `dayseven.exe`, the Flutter DLLs and `data/`, so installing is
extracting it and uninstalling is deleting it. No admin rights, and no signing
certificate — the cost is a one-time SmartScreen warning on first run. Knowledge Bases go wherever the user picks, through the
system folder picker.

To build for Windows without owning a Windows machine, open the repository's
**Actions** tab, choose **Build Windows release**, and select **Run workflow**.
Download the `DaySeven-Windows-x64` artifact when the job finishes.

Both workflows copy the checked-in `env/supabase.production.json` client
configuration into the build. The Supabase publishable key is intended for
client applications; database authorization remains enforced by RLS policies.

## Installing

Both platforms install by unpacking an archive, once:

- **macOS** — open `DaySeven.dmg` and drag the app to Applications. It must
  live there; DaySeven replaces its own bundle when it updates, and refuses to
  do that from anywhere else.
- **Windows** — extract `DaySeven-Windows-x64.zip` somewhere writable, under
  your user folder rather than Program Files, and run `dayseven.exe`. Windows
  warns once that it does not recognise an unsigned application: choose **More
  info**, then **Run anyway**.

That is the only manual download. Everything after it goes through **Menu ->
Settings -> Run updates**.

## Releasing

One version, in one place. `version:` in `pubspec.yaml` is the source of
truth — `scripts/pubspec_version.sh` and its PowerShell twin read it, and the
storage paths and the release row are derived from it. Bump the build number
for every release, not just the patch: two builds of the same version are
distinguished only by it.

```bash
# 1.3.0+5 -> 1.3.1+6, then:
git tag v1.3.1 && git push origin v1.3.1
```

The tag fires both workflows. Each checks the tag against the pubspec, builds,
uploads to the `releases` bucket in Supabase, and calls `publish_release` to
make the new build current. Tagging is the only thing that publishes; pull
requests build but never touch the live feed.

One repository secret is required, `SUPABASE_SERVICE_ROLE_KEY`, which writes
the release feed and bypasses RLS. Set it without the value touching a command
line:

```bash
gh secret set SUPABASE_SERVICE_ROLE_KEY   # prompts, and does not echo
```

To roll a release back, clear `is_current` on its row and set it on the
previous one; the next check stops offering it.

## How updates reach people

There is no installer and no code signing certificate on either platform.
DaySeven is a folder of files — an `.app` bundle on macOS, a directory of
executables on Windows — and updating is replacing that folder.

**Menu -> Settings** is the one place settings live. A rail down its left
side lists the regions this build actually has: *General*, which is the version
and updates; *Knowledge Base*, which is sharing and collaborators for the open
folder; and *Developer*, when a build has developer options. The gear beside
the Knowledge Base tree opens the same dialog on its own section rather than a
second one of its own — there is one settings surface, not two.

Opening it reads `app_releases` and compares the current row against the
running build, so the dialog opens already saying whether this copy is
current. **Run updates** then acts on that answer: it downloads the
archive, checks it against the published SHA-256, unpacks it beside the
install, and swaps it in — or re-checks, if there was nothing to install.

The swap cannot be done by the process being replaced, so
`lib/shared/platform/app_update.dart` ends the same way on both platforms:
write a short script, start it detached, and quit. The script waits for the
app to exit, replaces the files, and reopens it. On macOS the old bundle is
moved aside first, so a failure leaves a working app rather than nothing.

Nothing checks for updates on its own, and nothing updates in the background:
the check runs when Settings is opened, and the install when it is asked
for. An old build keeps working until somebody asks it not to.

### The release feed

`public.app_releases` holds one current row per platform and channel. It is
the only table in the schema `anon` may read — every other row belongs to
somebody, and this one is the public fact of which build is current. It has to
be readable signed-out, because the person most in need of an update is the
one whose old build cannot sign in.

Nothing client-side can write it: there is no insert or update policy, and
`publish_release` is granted to `service_role` alone.

The `releases` storage bucket is public, unlike `kb-assets`. These are the
same build artifacts anyone is invited to download and run, and nothing in
them belongs to a user.

## Tests

```bash
flutter test
./scripts/check_layers.sh
```

Covers the palette's contrast ratios, the block model's JSON round-trip, the three-way merge (including
formatting survival and the conflict case), the Knowledge Base on disk and its
layout migrations, moving items between folders, live folder watching, FTS5
search, ODT/DOCX round-trips in
both directions and across formats, the rich text controller, the editor's block
behaviour, presence folding and the chrome it drives, and the shell's layout
rules.

`test/app/appearance_test.dart` renders the shell to `test/app/goldens/`. Those
images are how the layout is meant to look — they caught a real misalignment
between the islands — but like all golden tests they are sensitive to the
Flutter and font versions that produced them. There is one set of them, because
there is one appearance. Refresh with:

```bash
flutter test test/app/appearance_test.dart --update-goldens
```
