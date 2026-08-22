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
                   and the sharing that syncs them
  features/      One folder per feature: ui/, plus state/, data/ or domain/
    auth/          The sign-in button
    editor/        The document editor and its rich-text controller
    home/          The landing screen
    knowledge_base/The right-side menu, dialogs, and KB repository
    review/        Diff view, three-way merge, proposals, change sets
    search/        Query state and the search bar
    views/         The left-side Home and Editor navigation menu
  shared/        Used by more than one feature; depends on no feature
    blocks/        Block model, revisions, the FTS5 search index — pure Dart
    kb/            Knowledge Base bundle: the folder on disk
    documents/     ODT and DOCX import/export
    auth/          Who is signed in
    backend/       Supabase client, error vocabulary, document repository
    platform/      Install-location check
    ui/            Theme tokens, controls, menus, dialogs, span styling
supabase/
  migrations/    Schema, RLS, RPCs, Realtime trigger, Storage bucket
scripts/         Packaging for macOS (DMG) and Windows (MSIX)
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
editor edits the open document, but search, review, home and the KB menu all
read it too.

Application-wide preferences live together in
`shared/ui/global_settings.dart`. Add future global settings to `DsAppSettings`
so the composition root can rebuild the whole app from one listenable value.
Text in controls, menus, navigation and other application chrome must use
`uiTextStyle`; document titles, prose, headings, tables, captions and code must
use `editorTextStyle`. Their sizes scale from the independent UI and editor base
sizes in the global settings rather than from feature-local constants.

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
| A collaborator saves | Their local file is written; nothing upstream changes |
| They choose *Propose changes* | A `change_set` is created with `base_revision_id` and the full proposed JSON |
| Realtime fires | A private channel carries only ids and the author's display name — never content |
| You open the toolbar's ellipsis menu and choose *Differences* | The proposal is fetched and shown: your file left, the proposal right |
| **Approve** | A three-way merge runs, then one server-side transaction writes the new revision; only then is your file rewritten |
| **Reject** | The proposal is marked rejected. No revision is written, your file is untouched |
| **Return** | The diff closes and the proposal stays pending |

The merge aligns paragraphs by their stable ids and merges *within* a paragraph
at character level, with formatting attached to the characters it applies to.
That is what lets one person bold a phrase while another rewrites a different
sentence and keep both. Where the two genuinely overlap, the proposal wins and
the block is marked as conflicted in the diff before you approve.

## Interface

- **Three panes** — the Views menu, the editor and the Knowledge Base menu
  are rounded panes on the application background, each a subtle tone apart.
- **Left** — a Geist Pixel heading, *Views*, above a rounded island containing
  Home and Editor.
- **Top** — a persistent search bar over the Knowledge Base's local FTS5 index,
  matching as you type.
- **Right** — a Geist Pixel *Knowledge Base* heading, a rounded control naming
  the open folder, and a separate hierarchy island beneath it. The tree shows
  folder and document icons, and a line running down from each folder that
  turns in to meet its children. Drag a document or folder onto another folder
  to move it, or onto the panel background to bring it back out to the top
  level; the file is renamed on disk, not copied. Right-click a document to
  rename it, or edit its title in the editor and press Enter or click away; the
  Markdown filename is the canonical title everywhere. Right-click any item to
  delete it after a permanent-deletion confirmation.
- **Resizing** — drag the gap between the three panes. The editor keeps a
  minimum width however far you drag, and the widths are remembered between
  sessions.
- **Bottom** — an editor-width toolbar island with extra vertical breathing
  room. Formatting controls stay as individual buttons; an ellipsis menu holds
  *Differences* and carries a subdued dot when a proposal is waiting.
- **Top right** — one rounded button: "Sign in" when signed out, your display
  name when signed in, opening a short menu to change that name or sign out.
- **Home** — "Welcome back!" in Archivo, and recent files.

Accounts are **username and password**. The username is what a collaborator
invites you by; the display name is what they see on a proposal. Sharing a
Knowledge Base and inviting someone to it sit in the Knowledge Base dropdown,
since they belong to the Knowledge Base rather than to the account.

Formatting comes from the toolbar in the bottom bar — headings, bold, italic,
strikethrough, underline and the three alignments — from keyboard shortcuts
(⌘/Ctrl+B, I, U, ⇧⌘X), and from a context menu on a block for the rest: colour,
highlight, font, spacing, block kind, images, tables, footnotes and export.

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
elsewhere shows a dismissible notice and continues. The App Sandbox is
deliberately off: DaySeven ships as a signed, notarised DMG rather than through
the App Store, and the sandbox would make reopening a recent Knowledge Base
folder fail without security-scoped bookmarks.

**Windows 11.** Packaged as MSIX — per-user install, no admin rights, OS-managed
updates and uninstall. Knowledge Bases go wherever the user picks, through the
system folder picker.

To create a Windows installer without owning a Windows machine, open the
repository's **Actions** tab, choose **Build Windows MSIX**, and select **Run
workflow**. Download and extract the `DaySeven-Windows-x64` artifact when the
job finishes. It contains the `.msix`, its test certificate, and installation
instructions. Artifacts expire after 30 days; anyone downloading from the
private repository needs repository access, but the downloaded ZIP can be sent
directly to a trusted friend.

The workflow requires `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` repository
secrets. It stops before packaging when either is absent, so it cannot publish
an installer whose account controls have no configured backend.

The workflow's certificate is self-signed and intended for trusted test
distribution. A production release should use a persistent, publicly trusted
Authenticode certificate. macOS signing and notarisation are documented in
`scripts/build_macos.sh`.

## Tests

```bash
flutter test
./scripts/check_layers.sh
```

Covers the block model's JSON round-trip, the three-way merge (including
formatting survival and the conflict case), the Knowledge Base on disk and its
layout migrations, moving items between folders, live folder watching, FTS5
search, ODT/DOCX round-trips in
both directions and across formats, the rich text controller, the editor's block
behaviour, and the shell's layout rules.

`test/app/appearance_test.dart` renders the shell to `test/app/goldens/`. Those
images are how the layout is meant to look — they caught a real misalignment
between the islands — but like all golden tests they are sensitive to the
Flutter and font versions that produced them. Refresh with:

```bash
flutter test test/app/appearance_test.dart --update-goldens
```
