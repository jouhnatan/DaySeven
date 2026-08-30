# Cream & Fern — build reference

**Binding spec. Read before writing any UI code, and consult it again for every new screen,
component, or state.** Values here are not suggestions: hex codes, sizes, weights, and
spacing are exact. If something you need is not described, follow §12 Extrapolation — do not
invent a new idiom. Every screen must pass §13 before it ships.

Single theme. Cream ground, one green accent, two typefaces. There is no dark variant and
none may be added.

---

## 1. Colour tokens

| Token | Hex | Use |
|---|---|---|
| `paper` | `#FAF7EC` | The ground. Every window, pane, card, menu, sheet. |
| `paperRaised` | `#FFFDF6` | Rare floating surface with no border. |
| `inset` | `#F0ECDC` | Recessed regions: nav rails, table headers, status blocks. |
| `bar` | `#EDE9D9` | Title bars, toolbars. |
| `hairline` | `#E1DBC4` | Divisions inside one surface: row separators, group dividers. |
| `line` | `#CFC8AE` | Edges of objects: buttons, inputs, cards, menus. |
| `ink` | `#1B201A` | Primary text and icons. |
| `muted` | `#5A6560` | Captions, helper text, timestamps, inactive labels. |
| `faint` | `#8A9089` | Disabled text and placeholders only. |
| `fern` | `#1C3A26` | **The accent.** Selection fill, primary button, toggle-on, focus ring. |
| `fernHover` | `#2A5638` | Hover/pressed on any fern fill. |
| `fernWash` | `#E9EEE4` | Selected row wash in dense lists. |
| `onFern` | `#F7F4E9` | Text/icons on fern. |
| `sage` | `#B7CDB6` | App mark, avatars, illustration, chart fills. |
| `onSage` | `#2A4433` | Text on sage. |
| `slate` | `#3E5A56` | Links. |
| `success` | `#3A6E4C` | Positive state. |
| `warning` | `#8A6A18` | Attention. Never below 14px. |
| `warningWash` | `#F2E7C4` | Warning banner fill; text on it is `ink`. |
| `danger` | `#7A3327` | Destructive and error. |
| `dangerWash` | `#F3E3DC` | Error banner fill; text on it is `ink`. |
| `hover` | `rgba(27,32,26,0.06)` | Universal hover wash. |
| `pressed` | `rgba(27,32,26,0.10)` | Universal pressed wash. |
| `scrim` | `rgba(14,18,12,0.40)` | Behind modals. |

**Laws**

- No white anywhere. `paper` is the lightest surface in the product.
- Maximum two fern elements per view: where you are, and what commits. Nothing else.
- Semantic colours describe state only — text plus a small mark, or a full-width banner. Never an accent.
- No dark chrome. Fern is the only dark mass permitted on screen.
- Depth is drawn with borders, not shadows (§4).

Contrast (measured): ink/paper 15.4:1 · muted/paper 5.7:1 · onFern/fern 11.3:1 ·
slate/paper 7.0:1 · success/paper 5.6:1 · danger/paper 8.4:1 · warning/paper 4.7:1.
Non-text (borders only): line/paper 1.56:1 · hairline/paper 1.29:1.

---

## 2. Typography

Two families only. No third face, no monospace, no icon font with letterforms.

**Solway** — small headers only. Window titles, pane titles, card and tile titles, section
headings, the app name, display type. Weight 500 in UI, 700 for display. Solway never
carries a value, a control label, or a sentence of prose.

**Instrument Sans** — everything else, **always weight 400**. Body copy, control labels,
button labels, menu items, values, numbers, table cells, helper text, errors.

| Role | Family | Size / line-height | Weight | Colour |
|---|---|---|---|---|
| Display | Solway | 34 / 38 | 700 | `ink` |
| Title large | Solway | 22 / 28 | 500 | `ink` |
| Title | Solway | 16 / 22 | 500 | `ink` |
| Title small | Solway | 14.5 / 20 | 500 | `ink` |
| Body large | Instrument Sans | 15 / 23 | 400 | `ink` |
| Body | Instrument Sans | 13.5 / 20 | 400 | `ink` |
| Caption | Instrument Sans | 12.5 / 17 | 400 | `muted` |
| Caption small | Instrument Sans | 11.5 / 14 | 400 | `muted` |

**Rules**

- **Hierarchy comes from size and colour, never from weight.** There is no bold body text,
  no semibold label, no emphasised value. Sans is 400 everywhere without exception.
- A caption is Body one step down (12.5px) in `muted`. That is the only difference — do not
  also letterspace it, capitalise it, or change its family.
- Sentence case everywhere. No ALL-CAPS in the product, on any surface, at any size.
- Numbers are ordinary body text in Instrument Sans. No monospace, no separate numeric style.
- Prose caps at 66 characters per line. Helper text is one line; if it needs two, the label is wrong.

**Don't:** bold a word for emphasis, set a value in a heavier weight than its label, use
Solway for anything a user reads as content, or introduce a "strong" text style of any kind.

---

## 3. Spacing, size, shape

**Spacing scale (use nothing else):** `2, 4, 6, 8, 10, 12, 14, 16, 20, 22, 24, 32, 40, 56, 72`
Default gap between related controls is 12. Pane padding is 20–22. Region separation is 32+.

**Radius:** `0` full-bleed rows and table cells · `6` nav items, menu items, chips ·
`7` buttons, inputs, toolbar buttons · `8` segmented controls, menus, status blocks ·
`10` cards, tiles, dialogs, windows · pill only for a toggle track. Nothing exceeds 10.

**Heights (desktop):** button 36 · small/toolbar button 32 · icon button 32×32 · input 36 ·
menu item 32 · nav item 34 · list row 40 (dense 34) · tree row 30 · segmented cell 30 ·
toggle 22×38 · title bar 44 · toolbar 48. Wrap anything under 44px in a transparent 44px hit area.

**Borders:** 1px `hairline` inside a surface · 1px `line` around an object · 2px `fern` for
focus rings only. Never nest two borders — a bordered element inside a bordered container
drops its own.

---

## 4. Elevation

| Level | What | Treatment |
|---|---|---|
| Flat | Panes, cards, tiles, rows, toolbars | No shadow. 1px `line`. |
| Raised | Menus, popovers, tooltips | 1px `line` + `0 1px 2px rgba(27,32,26,.06), 0 8px 20px -10px rgba(27,32,26,.22)` |
| Window | Floating windows, sheets | 1px `line` + `0 1px 2px rgba(27,32,26,.08), 0 14px 36px -14px rgba(27,32,26,.30)` |
| Modal | Dialogs | Window shadow + `scrim` |

**Don't:** put a shadow on a card, tile, table row, nav item, or toolbar.

---

## 5. Menu and settings grouping

This governs every list of settings, every dropdown, and every nav rail.

- **Group items by purpose.** Items inside a group sit **2px** apart. Related settings rows
  sit directly adjacent, separated only by their own 1px `hairline` row separator.
- **Between groups leave 20px**, with a **1px `hairline` horizontal bar centred in the gap —
  10px of clear space above it and 10px below.** The bar spans the content width, inset by
  the container's horizontal padding, never edge-to-edge across the padding.
- Unrelated destinations must never touch. *"Knowledge base" and "Invite people" belong to
  different groups: they get the divider and the full 20px gap, not a 2px gap.*
- A group may carry a header: Caption size, `muted`, sentence case, 6px above the first item.
  Never capitals, never a background fill.
- Maximum 6 items per group. Beyond that, split into two groups or move to a submenu.
- The destructive group is always last, separated by 24px rather than 20px.
- Nav rails follow the same rule: 2px between items, 20px + divider between sections.

**Don't:** separate groups with a coloured band, a filled header row, extra indentation, or
a divider without padding around it.

---

## 6. Components

Each entry is the whole spec. Match it exactly.

**Button** — 36px tall, radius 7, 17px horizontal padding, label Body (13.5px, Sans 400).
Primary: `fern` fill, `onFern` label, `fernHover` on hover, one per view. Secondary: `paper`
fill, 1px `line`, `ink` label, `inset` on hover. Quiet: transparent, `hover` wash on hover.
Destructive: `paper` fill, 1px `line`, `danger` label. Disabled: `inset` fill, `faint` label.
*Don't* use a fern fill for a destructive action or place two primaries on one surface.

**Toolbar** — 48px tall, `bar` fill, 1px `hairline` bottom border, 12px horizontal padding.
Contains individually framed buttons: 32px tall, `paper` fill, 1px `line`, radius 7, 6px
apart, icon 16px, optional label at Body. Active mode: `fern` fill, `onFern` icon, persists.
Clusters separated by 12px plus a 1px × 20px `line` divider. Overflow collapses into a single
framed ⋯ button opening a dropdown. *Don't* wrap a toolbar to a second row or use bare
unframed icons.

**Toggle switch** — booleans only. Track 38×22 pill, thumb 16px. Off: `line` track, `paper`
thumb. On: `fern` track, `paper` thumb. 180ms ease. Always the right-hand element of its row,
label left at Body, optional one-line helper beneath at Caption. *Don't* use a toggle to
select objects or a checkbox to change a setting.

**Segmented control (switch states)** — 2 to 4 exclusive options, all worth showing. One
frame: `inset` fill, 1px `hairline`, radius 8, 2px inner padding. Cells 30px tall, radius 6,
13px horizontal padding, labels at Caption size (12.5px, Sans 400) in `muted`. Selected cell:
`paper` fill, `ink` label, 1px soft shadow — same 400 weight as the others. *Don't* bold the
selected cell, add a checkmark, or use this for five or more options.

**Checkbox** — object selection only. 18×18, radius 4, 1px `line`, `paper` fill. Checked:
`fern` fill, `onFern` tick.

**Text field** — 36px tall, `paper` fill, 1px `line`, radius 7, 12px padding, Body text,
`faint` placeholder. Label above at Body; helper below at Caption. Focus: `fern` border plus
a 2px `fern` ring offset 2px. Error: `danger` border and a one-line Caption message in
`danger` that states the fix. *Don't* use a placeholder in place of a label.

**Dropdown menu** — `paper`, 1px `line`, radius 8, raised shadow, 6px padding, min-width 180,
max-width 320, opens 4px below its anchor and flips when short of room. Items 32px tall,
radius 6, 10px padding, label at Body; optional 16px leading icon in `muted`; shortcut
right-aligned at Caption in `faint`. Hover fills with `hover`. Checked item shows a 14px
`fern` tick in the leading slot — the label does not change. Destructive item is `danger`
text with a `dangerWash` hover. Grouping follows §5. Fade + 4px rise, 140ms. *Don't* nest
more than one submenu level or exceed 60% of window height without scrolling.

**Nav rail** — vertical, left, 168–220px wide, `inset` fill, 1px `hairline` right border,
12px/10px padding. Items 34px tall, radius 6, 11px padding, Body labels in `muted`. Selected:
solid `fern` fill, `onFern` label, weight unchanged. Grouping follows §5. *Don't* show
selection with weight, an indent, or a left bar.

**Tabs** — within one region only. Labels at Body in `muted`, selected in `ink` with a 2px
`fern` underline, 1px `hairline` baseline across the full width, 20px between tabs.

**Tree / folder hierarchy** — rows 30px, indent 16px per level, depth capped at 5. Caret is
an 8px triangle in `muted` in a 20px hit box, rotating 90° in 140ms. A 1px `hairline` guide
rail at each ancestor's indent. Folder icon 16px `muted`. Name at Body, truncating in the
middle. Trailing count at Caption. Selected row: full-bleed `fern`, `onFern` text and icons.
Hover: `hover` wash. Drag target: 2px `fern` insertion line between rows, or a 2px `fern`
outline on the folder. Expanded empty folder shows one `Empty` row at child indent in
`faint`. *Don't* animate subtrees or nest a scroll area per level.

**Table / list** — header `inset`, 34px, Caption labels in `muted`, 1px `hairline` beneath.
Rows 40px, 1px `hairline` between, `hover` on hover, `fernWash` when selected. Text columns
left, quantities right. Row actions appear on hover at the right as 28px quiet icon buttons.
*Don't* fill a selected row with solid fern — solid fern is for navigation.

**Card / bento tile** — `paper`, 1px `line`, radius 10, 16px padding, no shadow, no hover
lift. Title at Title (Solway 16). One primary datum at 28px Sans 400. One supporting line at
Caption. Maximum one fern element per tile. Grid: 12 columns, 12px gutter, 88px row unit, on
an `inset` ground. Three layouts: hero 8×2 with 4×1 satellites; uniform 4×1 wrapping; 3×3
rail beside a 9-column region. Below 900px everything becomes full width in source order.
*Don't* reorder tiles responsively or put two fern elements in one tile.

**Dialog** — `paper`, 1px `line`, radius 10, modal shadow over `scrim`, 22px padding, max
480px wide. Title at Title, body at Body large, actions bottom-right with 12px between them:
quiet Cancel, then primary. Destructive confirm uses a `danger` fill.

**Status block** — `inset`, 1px `hairline`, radius 8, 13px padding. 19px semantic glyph, a
Body headline naming the state, a Caption sub-line carrying the timestamp, optional secondary
button at the right. Inverts to `fern`/`onFern` only when the state is actionable.

**Sync / background activity** — one row, 56px, `paper`, 1px `line`, radius 10, 12/14
padding, 12px gaps: semantic 19px mark · Body title naming **the state** · Caption sub-line
carrying the checkable fact · optional Caption count · trailing framed 32px button · a 2px
`fern` progress line pinned to the row's bottom edge, present only while work runs.
States: Synced (`success`, "Up to date" / "Synced 2 minutes ago") · Syncing (`fern`, rotating
mark, "Syncing" / "12 of 40") · Paused (`muted`) · Offline (`warning`, "Last synced yesterday
at 21:40") · Failed (`danger`, sub-line states the fix). Elsewhere: a 24px chip in chrome, a
2px `fern` spine plus `fernWash` on individual list rows being worked on. *Don't* use a
coloured dot as a status, name the feature instead of the state, omit the timestamp, or show
two activity indicators on one surface.

**Banner** — full width inside its pane, radius 8, `warningWash` or `dangerWash` fill, 1px
border in the matching semantic colour at 35%, `ink` text at Body, one sentence, one action
at the right.

**Chip / badge** — 24px tall, radius 6, 9px padding, Caption small text. Pairs: `fernWash`
with `success`, `warningWash` with `warning`, `dangerWash` with `danger`, `inset` with `muted`.

**Progress** — linear only. 16px tall including a 1px `line` frame, `paper` interior, `fern`
fill drawn as 6px blocks with 2px gaps, width animated on a stepped curve. Percentage sits
right at Caption.

**Tooltip** — `ink` fill, `paper` text at Caption, radius 6, 8×10 padding, 400ms delay. The
only place ink is used as a surface. Required on every icon-only control, alongside an
accessible label.

**Empty state** — centred, 34px padding: 46px `sage` glyph tile at radius 11, Title heading,
one Caption sentence up to 40 characters wide, one primary button. Every list, tree, and grid
needs one.

**Icons** — stroke only, 1.6px, rounded caps and joins, drawn on a 20px grid, rendered at
16/20/24. `muted` at rest, `ink` when active, `onFern` on fern. No filled sets, no duotone,
no emoji in the interface.

---

## 7. Layout

- App shell: title bar (44px, `bar`, hairline bottom) → optional toolbar (48px) → body.
- Body: nav rail (168–220px, `inset`) │ optional list column (260–320px) │ content pane.
- Dividers between columns are 1px `hairline`; a draggable divider adds an 8px invisible hit
  area and a resize cursor.
- A settings or detail pane is **one column**. If it needs two, it needs two panes.
- Pane padding 20–22px. Content max width for prose 66 characters.

---

## 8. Motion

140ms hover, colour, caret · 180ms toggles and menus · 220ms pane transitions ·
`ease-out` · nothing over 240ms · nothing bounces or parallaxes.
The one exception: a continuous activity rotation runs 900ms per turn, linear, and only while
work is actually happening. Under reduced motion, drop every animation and keep end states.

---

## 9. Voice

Sentence case. Active voice. Buttons are verbs with objects ("Install 1.4.0", never "OK"),
and the result is reported in the same words ("Installed 1.4.0"). Errors say what happened
and what to do. Name things as the user does. No exclamation marks, no apologies, no
marketing adjectives inside the product.

---

## 10. State and feedback

- Every state that can go stale carries a timestamp.
- Every list, tree, grid, and search has a designed empty state.
- Every destructive action has a confirm dialog naming the object.
- Loading uses a skeleton in `inset` at the final layout's shape, never a spinner in a pane.
- Success is reported in place, not in a toast, when the user is looking at the thing.

---

## 11. Accessibility

Focus ring is 2px `fern`, 2px offset, matching the control's radius, never removed.
All interactive text meets 4.5:1; `faint` is for disabled only. Full keyboard support: tab
order, arrow keys inside rails, trees, menus, and segmented controls, `Esc` closes, `Enter`
commits. Icon-only controls carry both a tooltip and an accessible label. Never rely on
colour alone to carry meaning.

---

## 12. Extrapolation — when this file is silent

1. Reuse the nearest component's geometry exactly — height, radius, border, padding.
2. Take every new value from the scales in §3.
3. If the element is neither "where you are" nor "what commits", it does not get fern.
4. Prefer a hairline to a fill; prefer a fill to a shadow.
5. Give any stale-able state a timestamp.
6. Name it as the user would, not as the system does.
7. One primary action per surface.
8. When in doubt, do less: a quieter version of an existing pattern beats a new device.

Free choices: icon glyphs, microcopy within §9, screen composition, skeleton shapes, chart
internals — provided §1–§5 hold.

---

## 13. Ship checklist

- [ ] No white surfaces; everything is `paper`, `bar`, or `inset`.
- [ ] At most two fern elements per view.
- [ ] All Instrument Sans text is weight 400 — no bold, no semibold, no emphasised values.
- [ ] Captions are 12.5px `muted` and differ from Body in nothing else.
- [ ] Headers are Solway; Solway carries no values or prose.
- [ ] No monospace, no ALL-CAPS, no third typeface.
- [ ] Menu and settings groups are 2px inside, 20px apart, with a hairline bar carrying 10px
      of padding above and below.
- [ ] Every spacing, radius, and height came from §3.
- [ ] Booleans are toggles; 2–4 exclusive options are a framed segmented control; 5+ is a menu.
- [ ] Cards flat, menus raised, dialogs scrimmed.
- [ ] Every stale-able state shows a timestamp; no status is carried by a dot alone.
- [ ] Focus rings visible everywhere; icon-only controls have tooltips and labels.
- [ ] Every list, tree, and grid has an empty state.
- [ ] Nothing animates longer than 240ms except a running activity spinner.

---

## 14. Never

Dark theme · dark title bar, sidebar, or footer · white surfaces · pure black · any hex
outside §1 · bold or semibold sans text · a "strong" or emphasised text style · monospace ·
a third typeface · ALL-CAPS labels · letterspaced small caps in product UI · shadows on
cards, tiles, rows, or nav items · gradients, blur, glassmorphism · a coloured hero · radius
above 10 · fern on decoration or on a third element · a bare coloured dot as status · a
status with no timestamp · emoji in the interface · animation over 240ms · bounce or elastic
curves · a toggle used for selection · a checkbox used for a setting · unframed icon buttons
in a toolbar · menu groups without a padded divider between them.
