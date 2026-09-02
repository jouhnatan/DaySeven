# `.unearth` files

A document is prose somebody wrote. An **object** is something the app
constructs. Objects live beside documents in the Knowledge Base folder, in
files with one extension — `.unearth` — and a `kind` at the root of the JSON
saying which sort of object this one is.

Today there is one kind: `timeline`.

## Why one extension

A map, when there is one, will be `"kind": "map"` in the same container rather
than a `.map.json` next to a `.timeline.json`. That keeps three things from
multiplying: the tree's idea of what is openable, the reader's idea of what it
can list, and `shared/kb`'s idea of what it is writing.

`shared/kb` stays generic about all of it. It knows the extension and how to
put JSON at a path; it does not know what a timeline is. Parsing belongs to
whichever feature owns the kind — `features/timeline/domain/timeline.dart` for
this one. That split is not stylistic: `shared/` may not import `features/`,
and `check_layers.sh` fails the build if it does.

## What a timeline looks like

```json
{
  "kind": "timeline",
  "version": 1,
  "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1",
  "title": "Third Age",
  "description": "",
  "items": [
    {
      "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e2",
      "type": "period",
      "title": "Rise of the North",
      "start": 1800,
      "startLabel": "1800",
      "end": 1850,
      "endLabel": "1850",
      "color": "amber"
    },
    {
      "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e3",
      "type": "event",
      "title": "The bridge falls",
      "start": 1842,
      "startLabel": "1842",
      "color": "fern",
      "document": "Places/Aldenmoor.md"
    }
  ]
}
```

### The envelope

| Field | Meaning |
| --- | --- |
| `kind` | Which object this is. Must be `"timeline"` to read as one. |
| `version` | The schema this file was written against. Currently `1`. |
| `id` | Stable identity, a UUID v7. Not the name. |
| `title` | Kept in step with the file name — see *The name is the file name*. |
| `description` | Free text about the timeline as a whole. May be absent. |
| `items` | Events and periods, in any order. May be absent or empty. |

### An item

`type` is `"event"` (a point in time) or `"period"` (a span). Anything that is
not `"period"` reads as an event.

| Field | Applies to | Meaning |
| --- | --- | --- |
| `id` | both | **Required.** Nothing could select an item without one. |
| `type` | both | `"event"` or `"period"`. |
| `title` | both | What the pill on the track says. |
| `start` | both | **Required.** The number the track plots against. |
| `startLabel` | both | What the user typed. See *Years and labels*. |
| `end` | period | Where the span ends. |
| `endLabel` | period | The typed form of `end`. |
| `color` | both | A `TimelineColor` id — `fern`, `amber`, `slate`, and so on. An unknown id falls back to `fern` rather than failing. |
| `document` | both | A Knowledge Base document this item stands for, relative to the Knowledge Base root, POSIX-style. Omitted entirely when there is no link. |

### Years and labels

`start` is a number so the track can place it; `startLabel` is what the person
typed, kept verbatim so an invented calendar survives a round trip.
`parseYearLabel` in `features/timeline/domain/timeline.dart` turns the second
into the first, and it is deliberately permissive — "Year 1803",
"20 Month 13, Year 1803" (a thirteenth month is fine), "1803-13-20",
"500 BCE" and plain "1803" all land somewhere sensible. A month is clamped
generously rather than to twelve: a world is allowed more months than ours has.

## Rules the code depends on

**A file is refused rather than repaired.** An unknown `kind`, or a `version`
higher than this build writes, throws `TimelineFormatException`. Opening such
a file and saving it back would quietly discard whatever the newer version
knew about, which is worse than declining to open it.

**Hand-edits are expected.** The file is written indented precisely so it can
be edited in a text editor without this app, so `fromJson` tolerates what that
produces: missing `items`, items out of order (they are sorted on the way in),
a period whose `end` is before its `start` (tidied, not refused). It does not
tolerate a missing `id` or `start` — those are the two fields nothing can work
around.

**An absent link and a link to nothing are the same thing.** `document` is left
out entirely rather than written as `null`, and the reader pane treats a link
whose document has since been deleted as a message rather than an error.

**The name is the file name.** As with documents, renaming the file renames
the thing. `TimelineController.open` overwrites `title` from the file name when
the two disagree, so there are never two names to reconcile.

## Objects are not documents

This is the important one.

`KnowledgeBase.readTree` lists documents. `documentPathsIn` walks that tree,
and everything downstream of it — the Supabase mirror, the FTS index, the CRDT
workspace store — reads each path it gets as Markdown. **An object in that list
would be parsed as Markdown by all three.** So objects are listed by
`readObjects` instead, which is a separate, flat walk.

`test/shared/kb/objects_test.dart` asserts this in both directions, and that
test exists to catch exactly this regression.

The consequence today is that **objects are local**: not synced to the server,
not searchable. That is a known gap rather than a design goal; wiring objects
through `documents`/`revisions` is separate work, and the reason it has not
been done casually is that the Realtime notification bus is trusted to be
server-authored (see the `kb:%` topic notes in `AGENTS.md`).

## Where the code is

| Concern | File |
| --- | --- |
| Extension, `isObjectPath`, read/write/create/rename, `readObjects` | `lib/shared/kb/bundle.dart` |
| Generic create/rename on the controller | `lib/app/workspace/kb_session.dart` |
| The timeline model, its JSON, `parseYearLabel` | `lib/features/timeline/domain/timeline.dart` |
| Open/edit/debounced-save of the open object | `lib/features/timeline/application/timeline_controller.dart` |
| Format tests | `test/features/timeline/timeline_test.dart` |
| Filesystem and listing tests | `test/shared/kb/objects_test.dart` |

## Adding a new kind

1. Write the model and its `toJson`/`fromJson` in the owning feature's
   `domain/`, with its own `kind` string and `version` starting at 1.
2. Seed new files through `KbController.createObject`, which takes the seed map
   — do not add a per-kind create method to `shared/kb`.
3. Filter `readObjects` by `kind` in the feature if it needs only its own; the
   listing is deliberately kind-blind.
4. Refuse an unknown kind and a higher version, for the reason above.

Nothing in `shared/` should need to change.
