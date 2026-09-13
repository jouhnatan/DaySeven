# `.unearth` files

A document is prose somebody wrote. An **object** is something the app
constructs. Objects live beside documents in the Knowledge Base folder, in
files with one extension — `.unearth` — and a `kind` at the root of the JSON
saying which sort of object this one is.

Today there are two kinds: `timeline` and `world`.

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
  "version": 3,
  "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1",
  "title": "Third Age",
  "description": "",
  "monthsPerYear": 12,
  "map": { "assetId": "0192f3aa-….png" },
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
| `version` | The schema this file was written against. Currently `3`. |
| `id` | Stable identity, a UUID v7. Not the name. |
| `title` | Kept in step with the file name — see *The name is the file name*. |
| `description` | Free text about the timeline as a whole. May be absent. |
| `monthsPerYear` | How many months this world's year has. Defaults to 12. Only used to place a dated item between one year mark and the next. |
| `map` | The map this timeline is drawn over, if one has been uploaded. Absent otherwise. |
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

### The map

```json
"map": { "assetId": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1.png" }
```

Only the asset id is kept. The image itself is copied into the Knowledge Base's
`.settings/assets/` by `KnowledgeBase.importAsset` — the same place a picture
in a document goes — so a map travels with the folder rather than pointing at
somewhere on one machine's disk the other machine has never heard of.

A map may only be a **PNG or a JPEG**. That is narrower than the images a
document accepts, deliberately: a map is one large picture that has to decode
every time the view opens, and the animated and multi-page formats have no
business being one. The file picker filters, and `setTimelineMap` enforces it
again — a file can also arrive by being renamed.

Clearing a map removes the reference and **leaves the image on disk**. Nothing
else refers to it, but deleting somebody's picture because they cleared a
reference to it is not a trade this app makes anywhere else either.

## What a World looks like

World format 4 keeps one geographic model, chooses only how to render it, and
carries the economy both the World and Economy views read:

```json
{
  "kind": "world",
  "version": 4,
  "id": "0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1",
  "title": "Aster",
  "renderMode": "2d",
  "model": {
    "sourceMapLayerId": "surface",
    "layers": [{
      "id": "surface",
      "name": "Surface Color",
      "type": "albedo",
      "assetId": "0192f3aa-….jpg",
      "projection": "equirectangular",
      "visible": true,
      "opacity": 1.0
    }],
    "landmarks": [{
      "id": "aldenmoor",
      "name": "Aldenmoor",
      "latitude": 52.4,
      "longitude": -3.1,
      "document": "Places/Aldenmoor.md"
    }]
  },
  "economy": {
    "resourceTypes": [
      { "id": "stone", "name": "Stone", "color": "slate" }
    ],
    "personTypes": [
      { "id": "0192f3aa-…", "name": "Soldiers", "color": "teal" }
    ],
    "locations": [{
      "id": "0192f3aa-…",
      "landmarkId": "aldenmoor",
      "population": 1200,
      "personCounts": { "0192f3aa-…": 40 },
      "resourceIds": ["stone"]
    }],
    "tradeRoutes": [{
      "id": "0192f3aa-…",
      "from": "aldenmoor",
      "to": "oakhaven",
      "resourceId": "stone",
      "controlPoints": [[0.34, 0.46], [0.66, 0.54]]
    }],
    "resourceNodes": [{
      "id": "0192f3aa-…",
      "resourceId": "stone",
      "latitude": 50.1,
      "longitude": -4.2,
      "homeLandmarkId": "aldenmoor"
    }]
  }
}
```

The PNG or JPEG pixels are copied to `.settings/assets/`; they are not encoded
inside JSON and the `.unearth` data is not written into image metadata.
`sourceMapLayerId` makes both 2D and 3D read the exact same asset. Landmarks
remain a table of latitude/longitude values in `.unearth`, so switching views
does not transform or duplicate them.

Both renderers use the same equirectangular projection. For longitude
$\lambda$, latitude $\phi$, image width $W$, and image height $H$:

$$
X = W\frac{\lambda+\pi}{2\pi},
\qquad
Y = H\frac{\pi/2-\phi}{\pi}
$$

Version 2 World files used an engine id and could carry Orogen layers. They are
read into the shared model, keep their existing asset ids, and are written back
as the current version. No image is rewritten or deleted during migration.
Version 3 files gain an empty economy plus the three built-in resources (Stone,
Timber, Gold).

### The economy

A **location** is a World landmark's economic profile, keyed by `landmarkId`.
Cities are landmarks: adding one in Economy adds a pin to the World, renaming
it renames the pin, and deleting it removes both. Only `category: "city"`
landmarks appear in Economy.

**Person types** and **resource types** are defined once on the World and
referenced by id, so renaming a type is a single edit. Deleting one removes it
from every city, node and route that used it.

**Trade routes** join two city landmarks. `controlPoints` are two `[u, v]`
pairs in the unit square of the equirectangular map, which keeps the curve
stable when the map image is replaced at a different pixel size. **Resource
nodes** are deposits at their own latitude and longitude; `homeLandmarkId`
names the city whose workers collect from them. Which resources a city
produces is `resourceIds` on its location.

The simulation itself — workers, cargo, stockpiles — is never written here. It
is rebuilt from this network each time the Simulate tab runs.

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

**Older files are upgraded, not refused.** Version 1 dated an item with a
single scalar `start`, and knew nothing about nations or about one document
being the main one: it is read as the year the scalar fell in, and its
`document` becomes the main document. Version 2 added those but had no map.
Either is read and written back at the current version. Only a *higher* version
is refused.

**Why the map earned a version bump** rather than being treated as an additive
field: a build that did not know about `map` would drop it on the next save,
and losing somebody's map quietly is worse than refusing to open the file. That
is the rule for any new field — if an older build silently discarding it would
lose something, bump.

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

The consequence used to be that **objects were local**. That is no longer
true for Worlds. A World (and therefore its economy and map) replicates through
the same explicit Sync path documents use:

- `public.kb_objects` and `public.kb_object_revisions` hold live objects and
  their append-only history; the object id inside the JSON is the row id, so an
  object keeps its identity across renames and machines.
- `publish_object` is the only writer, with the same `40001` optimistic-lock
  conflict documents use. Clients have no insert or update grant.
- `private.notify_object_published` publishes a metadata-only
  `object_published` event on the server-authored `kb:<kbId>` topic, which is a
  wake-up: the peer reads the durable rows before touching its files.
- The replicator treats objects like documents — never overwriting a divergent
  local file, counting that as a conflict — and syncs referenced assets through
  the same `kb-assets` bucket, which is what carries the map image.

Timelines still do not sync: `_syncableObjectKinds` in
`lib/app/workspace/kb_hierarchy_replicator.dart` names the kinds the build
replicates, and only `world` is in it. Adding a kind there is the whole switch;
the replication itself is kind-blind.

`test/shared/kb/objects_test.dart` asserts objects stay out of `readTree` in
both directions, and that test exists to catch exactly that regression.

## Where the code is

Everything about timelines — their model, their lifecycle, and every surface
that shows one — lives under `lib/features/timelines/`.

| Concern | File |
| --- | --- |
| Extension, `isObjectPath`, read/write/create/rename, `readObjects` | `lib/shared/kb/bundle.dart` |
| Generic create/rename on the controller | `lib/app/workspace/kb_session.dart` |
| The timeline model, its JSON, the upgrade path | `lib/features/timelines/domain/timeline.dart` |
| Open/edit/debounced-save, selection, nations, links | `lib/features/timelines/application/timeline_controller.dart` |
| The map surface, its upload, its pan and zoom | `lib/features/timelines/map_renderer/` |
| The editor, reader, strip and track | `lib/features/timelines/ui/` |
| Format tests | `test/features/timelines/timeline_test.dart` |
| Map tests | `test/features/timelines/map_upload_test.dart` |
| Filesystem and listing tests | `test/shared/kb/objects_test.dart` |
| The World and economy models, World v4 upgrade | `lib/shared/world/domain/` |
| World repositories and image metadata readers | `lib/shared/world/data/` |
| Open World, debounced save, providers | `lib/app/workspace/world_controller.dart`, `world_providers.dart` |
| The World view and its renderers | `lib/features/world/` |
| The Economy view | `lib/features/economy/` |
| Object sync repository and canonical hash | `lib/shared/backend/object_repository.dart` |
| Object replication and conflict rules | `lib/app/workspace/kb_hierarchy_replicator.dart` |

### `map_renderer/`

- `timeline_map_canvas.dart` — the surface itself: asks for a map when there is
  none, shows it with its controls when there is.
- `map_viewport.dart` — the pan and zoom engine. Holds a
  `TransformationController` rather than a scale-and-offset pair, because that
  is what carries the whole mapping between screen and image *including its
  inverse*. `toImagePoint` is that inverse, and exists now so the transform is
  never reduced to something that cannot express it — placing a pin is a point
  on the image that somebody clicked on the screen.
- `map_upload.dart` — what may be a map, and putting it on the timeline. Takes
  its dependencies explicitly rather than a provider container, so the rule is
  testable without a file dialog.

## Adding a new kind

1. Write the model and its `toJson`/`fromJson` in the owning feature's
   `domain/`, with its own `kind` string and `version` starting at 1.
2. Seed new files through `KbController.createObject`, which takes the seed map
   — do not add a per-kind create method to `shared/kb`.
3. Filter `readObjects` by `kind` in the feature if it needs only its own; the
   listing is deliberately kind-blind.
4. Refuse an unknown kind and a higher version, for the reason above.

A kind that should reach collaborators is one more edit: add its `kind` to
`_syncableObjectKinds` in `lib/app/workspace/kb_hierarchy_replicator.dart`. The
server tables are kind-blind, so no migration is needed; assets referenced by
`assetId` anywhere in the JSON sync automatically. A kind left out of that set
stays local, and nothing in `shared/` needs to know about it.
