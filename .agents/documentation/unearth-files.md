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
  "version": 2,
  "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1",
  "title": "Third Age",
  "description": "",
  "monthsPerYear": 12,
  "nations": [
    { "id": "n1", "name": "The Vale", "color": "teal" },
    { "id": "n2", "name": "The North", "color": "amber" }
  ],
  "items": [
    {
      "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e2",
      "type": "period",
      "title": "Rise of the North",
      "year": 1800,
      "end": 1850,
      "color": "amber",
      "nations": ["n2"]
    },
    {
      "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e3",
      "type": "event",
      "title": "The bridge falls",
      "year": 1842,
      "month": 3,
      "color": "fern",
      "document": "Places/Aldenmoor.md",
      "documents": ["Characters/Aldric.md"],
      "nations": ["n1", "n2"]
    }
  ]
}
```

### The envelope

| Field | Meaning |
| --- | --- |
| `kind` | Which object this is. Must be `"timeline"` to read as one. |
| `version` | The schema this file was written against. Currently `2`. |
| `id` | Stable identity, a UUID v7. Not the name. |
| `title` | Kept in step with the file name — see *The name is the file name*. |
| `description` | Free text about the timeline as a whole. May be absent. |
| `monthsPerYear` | How many months this world's year has. Defaults to 12. Only used to place a dated item between one year mark and the next. |
| `nations` | The powers this timeline knows about. May be absent or empty. |
| `items` | Events and ages, in any order. May be absent or empty. |

### A nation

Defined once on the timeline and referenced by the items party to it — rather
than written as free text on each item, so that renaming one is a single edit,
and rather than as a link to a document, so a nation can be named before
anybody has written it up.

| Field | Meaning |
| --- | --- |
| `id` | **Required.** What items reference. A nation without one is dropped. |
| `name` | What the chip says. |
| `color` | A `TimelineColor` id. Defaults to `slate`. |

An item referencing a nation the file does not define has that reference
dropped on read: an id nothing answers to would render as nothing at all.

### An item

`type` is `"event"` (a point in time) or `"period"` (a span). Anything that is
not `"period"` reads as an event.

| Field | Applies to | Meaning |
| --- | --- | --- |
| `id` | both | **Required.** Nothing could select an item without one. |
| `type` | both | `"event"` (a point) or `"period"` (an age). Anything else reads as an event. |
| `title` | both | What the pill on the track says. |
| `year` | both | **Required.** The year it happens in. |
| `month` | both | The month within `year`, or absent for something dated only to the year. |
| `end` | period | The year the age ends in. |
| `endMonth` | period | The month within `end`, or absent. |
| `color` | both | A `TimelineColor` id — `fern`, `amber`, `slate`, and so on. An unknown id falls back to `fern` rather than failing. |
| `document` | both | The **main** document: what the reader on the right shows. Relative to the Knowledge Base root, POSIX-style. |
| `documents` | both | Every other document the item connects to. Never repeats `document`. |
| `nations` | both | Nation ids, referencing the timeline's own `nations`. |

### Years and months

A year is a whole number and means whatever a year means in that world. A month
is an optional whole number above zero, and is deliberately unbounded: a world
is allowed a thirteenth month.

`monthsPerYear` on the timeline is what keeps such a calendar honest. It is used
for one thing only — placing a dated item between one year mark and the next —
so a month of 13 in a thirteen-month year lands just short of the following
year rather than spilling past it. Months have no names, so a date is said as
"Month 3, 1842".

### The main document

An item can connect to any number of documents, and exactly one of them is the
main one. That is what the reader on the right renders, and what the item is
really *about*; the rest are listed under it as connections.

The first document connected to an item becomes the main one, because an item
with one document and no main one would show nothing. Removing the main one
promotes another rather than leaving the reader empty while a document is
still connected.

## Rules the code depends on

**A file is refused rather than repaired.** An unknown `kind`, or a `version`
higher than this build writes, throws `TimelineFormatException`. Opening such
a file and saving it back would quietly discard whatever the newer version
knew about, which is worse than declining to open it.

**A version 1 file is upgraded, not refused.** Version 1 dated an item with a
single scalar `start`, and knew nothing about nations or about one document
being the main one. It is read as the year the scalar fell in, its `document`
becomes the main document, and it is written back as version 2. Only a *higher*
version is refused.

**Hand-edits are expected.** The file is written indented precisely so it can
be edited in a text editor without this app, so `fromJson` tolerates what that
produces: missing `items`, items out of order (they are sorted on the way in),
an age whose `end` is before its `year` (tidied, not refused), a `month` of zero
(read as no month), a nation id nothing defines (dropped). It does not tolerate
a missing `id` or `year` — those are the two fields nothing can work around.

**An absent value and an empty one are the same thing.** `month`, `document`,
`documents` and `nations` are left out entirely rather than written as `null` or
`[]`, and the reader pane treats a main document that has since been deleted as
a message rather than an error.

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
| The timeline model, its JSON, the v1 upgrade | `lib/features/timeline/domain/timeline.dart` |
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
