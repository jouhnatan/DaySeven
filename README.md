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
  app/         Theme tokens and application state (Riverpod)
  domain/      Block model, revisions, change sets, three-way merge — pure Dart
  kb/          Knowledge Base bundle: the folder on disk
  auth/        Signing in: the repository and the top-right button
  search/      The whole of search: FTS5 index, query state, the bar
  convert/     ODT and DOCX import/export
  sync/        Supabase client, repositories, Realtime, sharing
  ui/          shell, home, editor, diff
  platform/    Install-location check
supabase/
  migrations/  Schema, RLS, RPCs, Realtime trigger, Storage bucket
scripts/       Packaging for macOS (DMG) and Windows (MSIX)
```

Most of the tree is organised by layer. `auth/` and `search/` are the
exceptions: each is a feature folder holding everything that feature needs, so
its state, its logic and its controls stay together rather than being spread
across three layers.

## How a document is stored

Each document is a `.d7doc` file — JSON, one block per paragraph, with stable
block ids:

```
MyWorld/
  Characters/
    Aldric.d7doc
  Places/
    Aldenmoor.d7doc
  .settings/           the app's own files, hidden from the tree
    dayseven.kb.json   manifest: kbId, name, schemaVersion
    assets/            images referenced by documents
    .index/            search index (derived; safe to delete)
```

Creating a Knowledge Base scaffolds nothing but `.settings/` — the structure is
yours to make. A Knowledge Base from an earlier layout migrates the first time
it is opened, by renaming rather than copying.

The same JSON is what goes into `revisions.content` in Postgres and what the
diff view compares, so a document has one shape everywhere.

`.odt` and `.docx` are import and export formats, not the storage format.

## Reviewed collaboration

| Step | What happens |
|---|---|
| A collaborator saves | Their local file is written; nothing upstream changes |
| They choose *Propose changes* | A `change_set` is created with `base_revision_id` and the full proposed JSON |
| Realtime fires | A private channel carries only ids and the author's display name — never content |
| You press *Differences* | The proposal is fetched and shown: your file left, the proposal right |
| **Approve** | A three-way merge runs, then one server-side transaction writes the new revision; only then is your file rewritten |
| **Reject** | The proposal is marked rejected. No revision is written, your file is untouched |
| **Return** | The diff closes and the proposal stays pending |

The merge aligns paragraphs by their stable ids and merges *within* a paragraph
at character level, with formatting attached to the characters it applies to.
That is what lets one person bold a phrase while another rewrites a different
sentence and keep both. Where the two genuinely overlap, the proposal wins and
the block is marked as conflicted in the diff before you approve.

## Interface

- **Three islands** — the service rail, the editor and the Knowledge Base panel
  are rounded panes on the application background, each a subtle tone apart.
- **Left rail** — services, not tools: Home and Editor.
- **Top** — a persistent search bar over the Knowledge Base's local FTS5 index,
  matching as you type.
- **Right** — a band naming the open Knowledge Base, and beneath it the tree:
  folder and document icons, and a line running down from each folder that
  turns in to meet its children. Drag a document or folder onto another folder
  to move it, or onto the panel background to bring it back out to the top
  level; the file is renamed on disk, not copied.
- **Resizing** — drag the gap between any two islands. The editor keeps a
  minimum width however far you drag, and the widths are remembered between
  sessions.
- **Bottom** — one control, *Differences*, shown only while the Editor is
  active, with a subdued dot when a proposal is waiting.
- **Top right** — one rounded button: "Sign in" when signed out, your display
  name when signed in, opening a short menu to change that name or sign out.
- **Home** — "Welcome back!" in Aleo, and recent files.

Accounts are **username and password**. The username is what a collaborator
invites you by; the display name is what they see on a proposal. Sharing a
Knowledge Base and inviting someone to it sit in the Knowledge Base dropdown,
since they belong to the Knowledge Base rather than to the account.

Formatting is applied with keyboard shortcuts (⌘/Ctrl+B, I, U, ⇧⌘X) and one
context menu on a block. There is no toolbar.

Documents and folders are created from the island dropdown, or by right-clicking
a folder in the tree to create inside it.

The tree follows the folder as it changes: add, rename or delete a folder in
Finder or Explorer and it appears in the panel straight away, with new documents
picked up by search.

## Platform notes

**macOS.** The app belongs in `/Applications`; running a release build from
elsewhere shows a dismissible notice and continues. The App Sandbox is
deliberately off: DaySeven ships as a signed, notarised DMG rather than through
the App Store, and the sandbox would make reopening a recent Knowledge Base
folder fail without security-scoped bookmarks.

**Windows 11.** Packaged as MSIX — per-user install, no admin rights, OS-managed
updates and uninstall. Knowledge Bases go wherever the user picks, through the
system folder picker.

Both build scripts work unsigned. Signing and notarisation are documented in
`scripts/build_macos.sh` and `pubspec.yaml`'s `msix_config`, and need an Apple
Developer membership and an Authenticode certificate respectively.

## Tests

```bash
flutter test
```

Covers the block model's JSON round-trip, the three-way merge (including
formatting survival and the conflict case), the Knowledge Base on disk and its
layout migrations, moving items between folders, live folder watching, FTS5
search, ODT/DOCX round-trips in
both directions and across formats, the rich text controller, the editor's block
behaviour, and the shell's layout rules.

`test/ui/appearance_test.dart` renders the shell to `test/ui/goldens/`. Those
images are how the layout is meant to look — they caught a real misalignment
between the islands — but like all golden tests they are sensitive to the
Flutter and font versions that produced them. Refresh with:

```bash
flutter test test/ui/appearance_test.dart --update-goldens
```
