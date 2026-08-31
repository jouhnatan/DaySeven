# Cream & Fern — design system manual

A complete instruction set for redesigning a Flutter application in the Cream & Fern
system. Written to be handed to Claude Code as the single source of truth. Where this
document is silent, follow **§14 Extrapolation rules** rather than inventing a new idiom.

Target: **Flutter stable 3.47.x**, Material 3 (default — `useMaterial3` no longer needs
setting). Light theme only; there is no dark variant and one must not be added.

---

## 0. The one-paragraph brief

Cream & Fern is a quiet, paper-first desktop interface. The ground is warm cream, never
white. Structure is drawn with hairlines, never with filled bars or heavy chrome. Exactly
one saturated colour exists — a deep fern green — and it is spent no more than once or
twice per view, on the two things that matter: **where you are** and **the action that
commits**. Type does the hierarchy: a slab serif labels regions, a neo-grotesque carries
every word the user actually reads. Numbers are set in tabular figures in the same sans —
there is no monospace anywhere in the product.

---

## 1. Colour

### 1.1 The full palette — exact values

These hex values are the system. Do not shift, tint, or "improve" them.

| Token | Hex | Role |
|---|---|---|
| `paper` | `#FAF7EC` | The ground. Default surface for every window, pane, card, sheet, menu. |
| `paperRaised` | `#FFFDF6` | Only for a surface that floats above `paper` and must separate without a border (rare). |
| `inset` | `#F0ECDC` | Recessed surface: nav rails, table headers, status blocks, disabled fills, code blocks. |
| `bar` | `#EDE9D9` | Title bars and toolbars. Sits between `paper` and `inset`. |
| `hairline` | `#D5CEB4` | Internal divisions: row separators, dividers inside a surface. |
| `line` | `#C0B89A` | Object borders: input outlines, card edges, menu borders — and the seam between two regions. |
| `ink` | `#1B201A` | Primary text and icons. |
| `muted` | `#5A6560` | Secondary text: helper lines, timestamps, units, placeholder, inactive nav labels. |
| `faint` | `#8A9089` | Tertiary: disabled text, watermark, empty-state body. Never for anything actionable. |
| `fern` | `#1C3A26` | **The accent.** Selection fill, primary button, toggle-on, focus ring. |
| `fernHover` | `#2A5638` | Hover/pressed state of anything filled with `fern`. |
| `fernWash` | `#E9EEE4` | 8%-strength fern for selected-row washes in dense lists where a solid block is too loud. |
| `onFern` | `#F7F4E9` | Text and icons on top of `fern` / `fernHover`. A cream, never pure white. |
| `sage` | `#B7CDB6` | The app mark, avatar fills, illustration, chart fills. Decorative only. |
| `onSage` | `#2A4433` | Text on `sage`. |
| `slate` | `#3E5A56` | Links and informational accents. The cool voice. |
| `success` | `#3A6E4C` | Positive state (up to date, saved, synced). |
| `warning` | `#8A6A18` | Attention, not failure (unsaved changes, quota near limit). |
| `warningWash` | `#F2E7C4` | Background for a warning banner. Text on it is `ink`. |
| `danger` | `#7A3327` | Destructive action and error state. |
| `dangerWash` | `#F3E3DC` | Background for an error banner. Text on it is `ink`. |
| `hover` | `rgba(27,32,26,0.06)` | Universal hover wash over any surface. |
| `pressed` | `rgba(27,32,26,0.10)` | Universal pressed wash. |
| `scrim` | `rgba(14,18,12,0.40)` | Behind modals. |

### 1.2 Contrast (measured, WCAG 2.1)

| Pair | Ratio | Verdict |
|---|---|---|
| `ink` on `paper` | 15.44:1 | AAA |
| `ink` on `inset` | 13.99:1 | AAA |
| `muted` on `paper` | 5.65:1 | AA all sizes |
| `muted` on `inset` | 5.12:1 | AA all sizes |
| `muted` on `bar` | 4.98:1 | AA all sizes |
| `onFern` on `fern` | 11.33:1 | AAA |
| `onFern` on `fernHover` | 7.67:1 | AAA |
| `fern` on `paper` | 11.64:1 | AAA |
| `slate` on `paper` | 6.99:1 | AA all sizes |
| `success` on `paper` | 5.57:1 | AA all sizes |
| `danger` on `paper` | 8.40:1 | AAA |
| `warning` on `paper` | 4.71:1 | AA normal text only — never below 14px |
| `onSage` on `sage` | 6.30:1 | AA all sizes |
| `line` on `paper` | 1.85:1 | Non-text; borders only |
| `hairline` on `paper` | 1.47:1 | Non-text; internal divisions only |

`faint` (`#8A9089`) measures ≈3.0:1 on `paper`. It is legal only for disabled controls and
decorative text. Never put a real message in it.

### 1.3 Colour laws

1. **White is not in the system.** No `#FFF` surface, ever. `paper` is the lightest thing on screen.
2. **One fern per view, two at most.** The selected nav item and the primary button. If a
   third fern element appears, one of the three is wrong.
3. **Fern never means "brand decoration".** It means *your position* or *this commits*.
4. **Semantic colours are not accents.** `success`/`warning`/`danger` appear only when
   describing state, and only as text + a small mark — never as a filled block larger than
   a 24px chip, except a full-width banner.
5. **Dark chrome is forbidden.** No dark title bar, no dark sidebar, no dark footer. Fern
   is allowed to be the only dark mass on screen.
6. **Depth comes from borders, not shadows.** See §5.
7. **Regions are seated, not floating.** Panes butt against each other and run to the window
   edge. Two adjacent regions meet on one shared 1px `line` seam — never a gap, never two
   abutting borders. A seated pane draws no border of its own; the shell draws the seam.

### 1.4 Flutter: the colour scheme

```dart
// lib/theme/cf_colors.dart
import 'package:flutter/material.dart';

abstract final class CF {
  static const paper       = Color(0xFFFAF7EC);
  static const paperRaised = Color(0xFFFFFDF6);
  static const inset       = Color(0xFFF0ECDC);
  static const bar         = Color(0xFFEDE9D9);
  static const hairline    = Color(0xFFD5CEB4);
  static const line        = Color(0xFFC0B89A);

  static const ink   = Color(0xFF1B201A);
  static const muted = Color(0xFF5A6560);
  static const faint = Color(0xFF8A9089);

  static const fern      = Color(0xFF1C3A26);
  static const fernHover = Color(0xFF2A5638);
  static const fernWash  = Color(0xFFE9EEE4);
  static const onFern    = Color(0xFFF7F4E9);

  static const sage   = Color(0xFFB7CDB6);
  static const onSage = Color(0xFF2A4433);
  static const slate  = Color(0xFF3E5A56);

  static const success     = Color(0xFF3A6E4C);
  static const warning     = Color(0xFF8A6A18);
  static const warningWash = Color(0xFFF2E7C4);
  static const danger      = Color(0xFF7A3327);
  static const dangerWash  = Color(0xFFF3E3DC);

  static const hover   = Color(0x0F1B201A); // 6%
  static const pressed = Color(0x1A1B201A); // 10%
  static const scrim   = Color(0x660E120C); // 40%
}

const cfColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: CF.fern,          onPrimary: CF.onFern,
  primaryContainer: CF.fernWash, onPrimaryContainer: CF.fern,
  secondary: CF.slate,       onSecondary: CF.paper,
  secondaryContainer: CF.inset, onSecondaryContainer: CF.ink,
  tertiary: CF.sage,         onTertiary: CF.onSage,
  error: CF.danger,          onError: CF.paper,
  errorContainer: CF.dangerWash, onErrorContainer: CF.ink,
  surface: CF.paper,         onSurface: CF.ink,
  surfaceDim: CF.inset,      surfaceBright: CF.paperRaised,
  surfaceContainerLowest: CF.paperRaised,
  surfaceContainerLow: CF.paper,
  surfaceContainer: CF.bar,
  surfaceContainerHigh: CF.inset,
  surfaceContainerHighest: CF.inset,
  onSurfaceVariant: CF.muted,
  outline: CF.line,          outlineVariant: CF.hairline,
  shadow: Color(0xFF1B201A), scrim: CF.scrim,
  inverseSurface: CF.fern,   onInverseSurface: CF.onFern,
  inversePrimary: CF.sage,
);
```

> `ColorScheme.background` / `onBackground` / `surfaceVariant` are deprecated. Use
> `surface` / `onSurface` / `surfaceContainerHighest`. Do not reintroduce the old names.

---

## 2. Typography

Two families. Nothing else — no monospace, no icon font with letterforms, no third face.

### 2.1 The pairing

**Solway** (slab serif) — *small headers only.* Window titles, pane titles, card titles,
section labels, the app name, and display type on empty states or marketing surfaces.
Solway labels regions. It never carries a value, a sentence of prose, or a control label.
Weights available: 300/400/500/700/800, no italics. Use **500** for UI headers and **700**
for display sizes.

**Instrument Sans** — *everything else.* Body copy, control labels, helper text, values,
numbers, table cells, menu items, buttons, tooltips, errors. Weights 400/500/600 (+italics,
which the UI does not use). **500** is the emphasis weight; do not use 600 inside dense UI —
reserve it for a page-level headline set in the sans.

### 2.2 Rules

1. **Sentence case everywhere.** No ALL-CAPS UI chrome, ever — not on title bars, not on
   table headers, not on eyebrow labels. If a label needs to recede, use `muted` and 12px,
   not capitals. (Letterspaced caps are permitted in one place only: a marketing eyebrow on
   a non-product surface.)
2. **No monospace.** Version strings, sizes, times, IDs, and percentages are Instrument Sans
   with `FontFeature.tabularFigures()`. Alignment was the only job the mono was doing.
3. **Numbers align.** Any digit that appears in a column, a right-aligned value slot, a
   table, or a meter gets tabular figures.
4. **Measure.** Running prose is capped at 66 characters. Helper text under a label is one
   line; if it needs two, the label is wrong.
5. **Solway is never bold-for-emphasis inside a sentence.** Emphasis inside prose is
   Instrument Sans 500.

### 2.3 Scale

| Role | Family | Size / line-height | Weight | Notes |
|---|---|---|---|---|
| Display | Solway | 34 / 38 | 700 | Empty states, onboarding, about |
| Title large | Solway | 22 / 28 | 500 | Page heading |
| Title | Solway | 16 / 22 | 500 | Pane and card titles |
| Title small | Solway | 14.5 / 20 | 500 | Window title bar |
| Body large | Instrument Sans | 15 / 23 | 400 | Prose, dialog body |
| Body | Instrument Sans | 13.5 / 20 | 400 | Default UI text, list rows, fields |
| Body strong | Instrument Sans | 13.5 / 20 | 500 | Selected item, status headline |
| Label | Instrument Sans | 13 / 16 | 400 | Buttons, menu items, tabs |
| Caption | Instrument Sans | 12.5 / 17 | 400 | Helper text, timestamps, units |
| Micro | Instrument Sans | 11.5 / 14 | 500 | Badges, chips, counts |

### 2.4 Flutter: fonts and text theme

```dart
// pubspec.yaml
dependencies:
  google_fonts: ^8.2.1
flutter:
  assets:
    - assets/google_fonts/   # bundle, do not fetch at runtime
```

Bundle the files as `assets/google_fonts/Solway-Medium.ttf`,
`Solway-Bold.ttf`, `InstrumentSans-Regular.ttf`, `InstrumentSans-Medium.ttf`,
`InstrumentSans-SemiBold.ttf`. Do **not** rename them and do **not** list them under
`fonts:` — google_fonts matches on the `<Family>-<Variant>` filename. Register the OFL
licence with `LicenseRegistry.addLicense(...)` at startup, and disable network fetching:

```dart
void main() {
  GoogleFonts.config.allowRuntimeFetching = false;
  runApp(const App());
}
```

```dart
// lib/theme/cf_type.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'cf_colors.dart';

const _tnum = <FontFeature>[FontFeature.tabularFigures()];

TextStyle _slab(double size, double height, {FontWeight w = FontWeight.w500, Color? c}) =>
    GoogleFonts.solway(
      fontSize: size, height: height / size, fontWeight: w,
      color: c ?? CF.ink, letterSpacing: 0.05,
    );

TextStyle _sans(double size, double height,
        {FontWeight w = FontWeight.w400, Color? c, bool tabular = false}) =>
    GoogleFonts.instrumentSans(
      fontSize: size, height: height / size, fontWeight: w,
      color: c ?? CF.ink, fontFeatures: tabular ? _tnum : null,
    );

final cfTextTheme = TextTheme(
  displayLarge:  _slab(34, 38, w: FontWeight.w700),
  displayMedium: _slab(28, 34, w: FontWeight.w700),
  displaySmall:  _slab(24, 30, w: FontWeight.w700),
  headlineLarge: _slab(22, 28),
  headlineMedium:_slab(19, 25),
  headlineSmall: _slab(16, 22),
  titleLarge:    _slab(16, 22),
  titleMedium:   _slab(14.5, 20),
  titleSmall:    _sans(13, 16, w: FontWeight.w500),
  bodyLarge:     _sans(15, 23),
  bodyMedium:    _sans(13.5, 20),
  bodySmall:     _sans(12.5, 17, c: CF.muted),
  labelLarge:    _sans(13, 16, w: FontWeight.w500),
  labelMedium:   _sans(12.5, 16),
  labelSmall:    _sans(11.5, 14, w: FontWeight.w500),
);

/// Any number the user compares or scans.
TextStyle cfNumeric(BuildContext c) =>
    Theme.of(c).textTheme.bodyMedium!.copyWith(fontFeatures: _tnum);
```

**Titles use `titleLarge`/`titleMedium` (Solway). Everything else uses body/label (sans).**
If a widget shows Solway on a value, it is a bug.

---

## 3. Space, size, shape

### 3.1 Spacing scale (4pt base)

`2, 4, 6, 8, 10, 12, 14, 16, 20, 22, 24, 32, 40, 56, 72`

Use `12` as the default gap between related controls, `20–22` as pane padding, `32+` only
between content regions *inside* a pane. Never invent a value outside the scale. Shell
regions get no spacing at all: panes butt together, run to the window edge, and are divided
by a 1px `line` seam rather than by a gap.

```dart
abstract final class Sp {
  static const xxs = 2.0, xs = 4.0, s = 8.0, sm = 12.0,
               m = 16.0, ml = 20.0, l = 24.0, xl = 32.0, xxl = 40.0;
}
```

### 3.2 Radius

Every rectangular surface is square. One token carries a non-zero value.

| Token | Value | Applied to |
|---|---|---|
| `rNone` | 0 | Everything rectangular: rows, cells, dividers, buttons, inputs, toolbar buttons, nav and menu items, chips, segmented controls, status blocks, menus, popovers, cards, bento tiles, dialogs, panes, windows |
| `rPill` | 999 | Toggle track and thumb, and count badges |

Genuinely circular elements — presence dots, avatars, colour swatches, status dots — stay
circles. Nothing else carries a rounded corner. The old `rSm`/`rMd`/`rLg`/`rXl` steps are
gone; do not reintroduce them, and never write a literal `Radius.circular(n)` in a widget —
use `BorderRadius.zero` (or the radius token) so the rule stays enforceable.

### 3.3 Control heights (desktop)

| Control | Height | Horizontal padding |
|---|---|---|
| Primary / secondary button | 36 | 17 |
| Small button, toolbar button | 32 | 13 |
| Icon-only button | 32 × 32 | — |
| Text input | 36 | 12 |
| Menu item | 32 | 10 |
| Nav rail item | 34 | 11 |
| List / table row | 40 (dense 34) | 12 |
| Tree row | 30 | indent + 8 |
| Segmented cell | 30 | 13 |
| Toggle | 22 × 38 | — |

On touch targets under 44px, wrap in a transparent 44px hit area — do not enlarge the visual.

### 3.4 Borders

- **1px `hairline`** — divisions *inside* one surface (row separators, group dividers).
- **1px `line`** — the edge of a nested *object* (input, card, menu, tile), and the **seam**
  between two regions.
- **2px `fern`** — focus ring only, offset 2px. Nothing else is 2px.
- Never a double border: a bordered card inside a bordered pane drops the inner border.
- Never two abutting borders: where two regions meet there is exactly **one** shared 1px
  `line` seam, drawn by the shell. A seated pane, title bar, toolbar or footer has no border
  of its own. Surfaces nested *inside* a pane keep their 1px border — they are just square.
- Buttons have no border at all except the primary's fill; inputs and the segmented control
  frame keep theirs.

---

## 4. The design philosophy

These are the decisions that produce the look. When a new screen has no precedent, these
sentences decide it.

1. **Spend ink where the answer is.** The heaviest element on screen must be the thing the
   user opened the screen to learn or do — not the word "Settings", not a header bar.
2. **Hairlines over fills.** Group by whitespace and a 1px rule. Do not put a tinted block
   behind something merely to group it. `inset` is for genuinely recessed regions.
3. **Labels left, values right.** In any label/value row: label in `ink` at body size on the
   left, value right-aligned, helper text under the label in `caption`/`muted`.
4. **State is a fact, with a time.** Never show a bare status word. "Up to date" is followed
   by "Checked today at 9:14 AM". Every synced/saved/imported state carries its timestamp.
5. **One column per pane.** A settings or detail pane is a single column of rows. If content
   needs two columns, it needs two panes.
6. **Position is shown by fill, not weight.** The selected nav item is a solid `fern` block
   with `onFern` text. Do not indicate selection with bold alone.
7. **Every control says what happens.** Button labels are verbs with objects — "Install
   1.4.0", not "OK". After the action, the UI states the result in the same words.
8. **Nothing is decorative.** Numbering, dividers, eyebrows and icons must encode something
   true. If a rule is there to look nice, delete it.
9. **Motion is functional and short.** 140–180ms. Colour, background, and small transforms
   only. Nothing bounces, nothing parallaxes.
10. **Empty is a state, not a gap.** Every list, tree, and grid has a designed empty state
    with one sentence and one action.

### 4.1 Control vocabulary — which widget for which decision

| The decision | The control | Never |
|---|---|---|
| A boolean setting | **Toggle switch**, right-aligned in its row | Checkbox, "on/off" segmented |
| Selecting rows/items for a bulk action | **Checkbox** (square, 18px) | Toggle |
| One of 2–4 exclusive options, all worth showing | **Segmented control** — word buttons inside a single framed strip | Radio list, dropdown |
| One of 5+ exclusive options | **Dropdown menu** | Segmented control |
| One of many, needing search | **Dropdown with filter** or a picker dialog | A very long menu |
| A command | **Button** — a verb; frameless unless it is the primary (a `fern` fill) | An icon alone in a content area |
| A command among many, repeated | **Toolbar button** — unframed, icon + optional label, in a horizontal row | An overflowing menu bar |
| Navigating between sibling regions | **Nav rail** (vertical, left) | Top tabs, unless ≤4 and shallow |
| Navigating within one region | **Tabs** (underline, sans labels) | A second nav rail |
| Destructive command | Frameless button with a `danger` label, or a `danger` fill in a confirm dialog | `fern` fill |

---

## 5. Elevation and shadow

Four levels only.

| Level | What | Treatment |
|---|---|---|
| 0 — seated | Panes, title bar, toolbar, footer | No shadow and no border of their own. Adjacent regions share one 1px `line` seam. |
| 0 — flat | Cards, bento tiles, table rows, fields nested in a pane | No shadow. 1px `line` border. |
| 1 — raised | Popovers, dropdown menus, tooltips, autocomplete | 1px `line` + `0 1px 2px rgba(27,32,26,.06), 0 8px 20px -10px rgba(27,32,26,.22)` |
| 2 — window | Floating windows, side sheets | 1px `line` + `0 1px 2px rgba(27,32,26,.08), 0 14px 36px -14px rgba(27,32,26,.30)` |
| 3 — modal | Dialogs over a `scrim` | Same as level 2, plus the scrim |

**Cards never carry a shadow.** If a card looks flat next to a menu, that is correct — the
menu is above the page and the card is on it. Menus, popovers and dialogs float, so they keep
both their 1px `line` border and their shadow; a seated region has neither.

```dart
const cfMenuShadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F1B201A), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x381B201A), blurRadius: 20, spreadRadius: -10, offset: Offset(0, 8)),
];
const cfWindowShadow = <BoxShadow>[
  BoxShadow(color: Color(0x141B201A), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x4D1B201A), blurRadius: 36, spreadRadius: -14, offset: Offset(0, 14)),
];
```

---

## 6. Core components

### 6.1 Window / page chrome

A cream title bar — **not dark**. Full-bleed, 44px tall, `bar` background, square, a 1px
`line` bottom seam and no other border, title in Solway `titleMedium` sentence case at the
left (optionally preceded by an 18px app mark), window/close controls at the right as 32px
icon buttons. There is no window margin: the bar runs to the window edge, and the body sits
directly beneath the seam.

```dart
PreferredSize(
  preferredSize: const Size.fromHeight(44),
  child: DecoratedBox(
    decoration: const BoxDecoration(
      color: CF.bar,
      border: Border(bottom: BorderSide(color: CF.line)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Sp.m),
      child: Row(children: [
        Text('Settings', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () {}),
      ]),
    ),
  ),
)
```

### 6.2 Buttons

| Variant | Fill | Border | Text |
|---|---|---|---|
| Primary | `fern` → `fernHover` on hover | none | `onFern`, label 500 |
| Secondary | transparent → `hover` on hover, `pressed` on press | none | `ink`, label 400 |
| Quiet | transparent → `hover` | none | `ink` |
| Destructive | transparent → `dangerWash` on hover | none | `danger` |
| Destructive-confirm (in dialog) | `danger` | none | `paper` |
| Disabled (any variant) | none | none | `faint` |

Every variant but the primary is **frameless** — a bare label/icon target. One primary per
view. Radius 0. Height 36 (32 for the small/toolbar size). Text inputs and the segmented
control frame are not buttons: they keep their 1px `line` frame, square.

```dart
final cfPrimaryButton = FilledButton.styleFrom(
  backgroundColor: CF.fern, foregroundColor: CF.onFern,
  disabledBackgroundColor: CF.inset, disabledForegroundColor: CF.faint,
  minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 17),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
  textStyle: cfTextTheme.labelLarge,
).copyWith(
  backgroundColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.disabled) ? CF.inset
      : s.contains(WidgetState.hovered) || s.contains(WidgetState.pressed) ? CF.fernHover
      : CF.fern),
);

// Secondary, quiet and destructive are all frameless: no side, no fill, a wash on hover.
final cfSecondaryButton = OutlinedButton.styleFrom(
  backgroundColor: Colors.transparent, foregroundColor: CF.ink,
  disabledForegroundColor: CF.faint,
  side: BorderSide.none,
  minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 15),
  shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
  textStyle: cfTextTheme.labelLarge?.copyWith(fontWeight: FontWeight.w400),
).copyWith(
  backgroundColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.pressed) ? CF.pressed
      : s.contains(WidgetState.hovered) ? CF.hover
      : Colors.transparent),
);

final cfDestructiveButton = cfSecondaryButton.copyWith(
  foregroundColor: const WidgetStatePropertyAll(CF.danger),
  backgroundColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.pressed) ? CF.pressed
      : s.contains(WidgetState.hovered) ? CF.dangerWash
      : Colors.transparent),
);
```

### 6.3 Toggle switch (booleans)

Track 38 × 22, pill. Off: `line` track, `paper` thumb. On: `fern` track, `paper` thumb.
Thumb 16px with a 1px soft shadow. 180ms ease. Always the right-hand element of its row;
the label is on the left with optional one-line helper beneath.

```dart
final cfSwitchTheme = SwitchThemeData(
  trackColor: WidgetStateProperty.resolveWith((s) =>
      s.contains(WidgetState.disabled) ? CF.hairline
      : s.contains(WidgetState.selected) ? CF.fern : CF.line),
  thumbColor: const WidgetStatePropertyAll(CF.paper),
  trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
  trackOutlineWidth: const WidgetStatePropertyAll(0),
  overlayColor: const WidgetStatePropertyAll(CF.hover),
);
```

**Row pattern** (the single most repeated composition in the product):

```dart
class CfSettingRow extends StatelessWidget {
  const CfSettingRow({super.key, required this.label, this.helper, required this.trailing, this.first = false});
  final String label; final String? helper; final Widget trailing; final bool first;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: first ? null : const BoxDecoration(
        border: Border(top: BorderSide(color: CF.hairline)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: t.bodyMedium),
          if (helper != null) Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text(helper!, style: t.bodySmall),
          ),
        ])),
        const SizedBox(width: 18),
        trailing,
      ]),
    );
  }
}
```

### 6.4 Segmented control (2–4 exclusive options)

Word buttons inside **one frame**: 1px `line`, square, 2px inner padding, `inset` fill.
Cells are label-only (13px), 30px tall, square. The selected cell is `paper` with a
1px/2px soft shadow and 500 weight — it reads as a raised chip inside the frame. On dense or
pixel-adjacent surfaces the selected cell may instead invert to `fern`/`onFern` with hard
2px `line` dividers between cells; pick one convention per app and keep it.

```dart
final cfSegmentedTheme = SegmentedButtonThemeData(
  style: ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? CF.paper : Colors.transparent),
    foregroundColor: WidgetStateProperty.resolveWith((s) =>
        s.contains(WidgetState.selected) ? CF.ink : CF.muted),
    textStyle: WidgetStatePropertyAll(cfTextTheme.labelMedium),
    side: const WidgetStatePropertyAll(BorderSide.none),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder(
        borderRadius: BorderRadius.zero)),
    padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 13)),
    minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
  ),
);
// Wrap the SegmentedButton in a Container with color: CF.inset,
// border: Border.all(color: CF.line), BorderRadius.zero, padding 2,
// and pass showSelectedIcon: false — the checkmark is not part of this system.
```

### 6.5 Text fields

36px tall, `paper` fill, 1px `line`, square, 12px horizontal padding, body text.
Focus: 1px border becomes `fern` **plus** a 2px `fern` ring offset 2px. Error: `danger`
border, message below in `caption`/`danger`, one line, stating the fix.
Label sits **above** the field in `bodyMedium`; placeholder is `faint` and never replaces a
label.

### 6.6 Status block

The pattern for "here is the current state of something": `inset` fill, 1px `hairline`,
square, 13px padding, a 19px semantic glyph, a `bodyMedium` 500 headline, a `caption`
`muted` sub-line carrying the timestamp, and an optional secondary button at the right.
When the state is *actionable* (an update is waiting), the block inverts to `fern` with
`onFern` text — this is the one place a large fern surface is allowed.

### 6.7 Progress

Linear only. 16px tall including a 1px `line` frame, `paper` interior, fern fill. Render the
fill as discrete 6px blocks with 2px gaps and animate width with a **stepped** curve — the
meter should read as counting, not sliding. A percentage label sits right, `muted`, tabular.

### 6.8 Tooltips, toasts, banners

- **Tooltip**: `ink` fill, `paper` text, square, 8×10 padding, caption size, 400ms delay.
  The one place ink is used as a surface.
- **Toast**: bottom-left, `paper`, 1px `line`, square, level-1 shadow, one sentence +
  optional "Undo" in `slate`. 6s.
- **Banner**: full-width inside its pane, square, `warningWash`/`dangerWash` fill, 1px
  border in the matching semantic colour at 35% (`warning`/`danger`), `ink` text, one
  sentence, one action on the right.

---

## 7. Folder hierarchies (tree view)

The tree is the system's densest surface; it earns special rules.

**Geometry** — row height 30 (dense 26). Indent **16px per level**, cap depth at 5. The
disclosure caret is an 8px solid triangle in `muted`, pointing right when collapsed and down
when expanded, sitting in a 20px hit box at the row's leading edge; it rotates 90° in 140ms.
A **1px `hairline` guide rail** is drawn at each ancestor's indent x-position so deep
children remain traceable. Icons are 16px, `muted` when unselected.

**Rows** — folder name in `bodyMedium`, truncated with ellipsis in the middle for long names
(preserve the extension). A right-aligned `caption`/`muted` tabular count or size. Selected
row is a full-bleed `fern` block, square, text and
icons in `onFern`, and the guide rails hidden inside the selection. Hover is `hover` wash.
Multi-select uses the same fill; the focus row adds a 2px `fern` ring.

**Interaction** — click toggles selection; click on the caret or double-click on the name
toggles expansion; `→`/`←` expand/collapse, `↑`/`↓` move, `Home`/`End` jump, type-ahead
selects. Drag-and-drop shows a **2px `fern` insertion line** between rows, or a 2px `fern`
outline around a folder when dropping *into* it. Never animate the whole subtree on drop —
fade the moved row in over 140ms.

**Empty folder** — a single row at child indent reading "Empty" in `faint`; do not show a
blank expansion.

**Flutter** — use the first-party `TreeSliver<T>` / `TreeSliverNode<T>` inside a
`CustomScrollView` with a custom `treeNodeBuilder`, or `two_dimensional_scrollables`
(publisher flutter.dev) `TreeView` if you need horizontal scrolling and row decorations.
`ExpansionTile` is acceptable only for a shallow two-level list, and needs
`ExpansibleController` (not the deprecated `ExpansionTileController`) plus a unique
`PageStorageKey`.

```dart
TreeSliver<FileNode>(
  tree: nodes,
  indentation: TreeSliverIndentationType.custom(16),
  treeNodeBuilder: (context, node, animation) {
    final selected = node.content.id == selectedId;
    return Container(
      height: 30,
      color: selected ? CF.fern : Colors.transparent,
      padding: EdgeInsets.only(left: 16.0 * node.depth! + 4, right: 12),
      child: Row(children: [
        SizedBox(width: 20, child: node.children.isEmpty ? null : AnimatedRotation(
          turns: node.isExpanded ? 0.25 : 0, duration: const Duration(milliseconds: 140),
          child: Icon(Icons.arrow_right, size: 16,
              color: selected ? CF.onFern : CF.muted))),
        Icon(node.children.isEmpty ? Icons.description_outlined : Icons.folder_outlined,
            size: 16, color: selected ? CF.onFern : CF.muted),
        const SizedBox(width: 8),
        Expanded(child: Text(node.content.name,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium!
                .copyWith(color: selected ? CF.onFern : CF.ink))),
        Text('${node.content.count}',
            style: Theme.of(context).textTheme.bodySmall!.copyWith(
              color: selected ? CF.onFern : CF.muted,
              fontFeatures: const [FontFeature.tabularFigures()])),
      ]),
    );
  },
)
```

---

## 8. Toolbar — unframed buttons in a horizontal list

The toolbar is a **row of unframed icon/label targets**. Nothing in it carries a frame; the
only filled button is one whose mode is active.

**Container** — full-bleed, 48px tall, `bar` fill, square, a 1px `line` seam on the edge
where it meets the next region (bottom for a header toolbar, top for a footer toolbar) and no
other border. It never carries a shadow and never goes dark.

**Buttons** — 32px tall, square, transparent fill, **no border**, 6px gap between siblings.
Icon-only buttons are 32×32 with a 16px glyph; labelled buttons take 13px sans with an 8px
icon-to-label gap. Hover: `hover` wash. Pressed: `pressed` wash.
**Toggled-on** (a mode is active): `fern` fill, `onFern` glyph — this is a state, not a
hover, and it persists.

**Clusters** — group related commands with the standard 6px gap; separate clusters with a
12px gap **and** a 1px × 20px `line` divider. Order clusters by frequency, left to right;
the destructive cluster is last and separated by 16px.

**Overflow** — never wrap to a second row. Below the width where all clusters fit, collapse
the right-most clusters into a single "More" button (⋯) that opens a dropdown containing the
same commands with the same labels and shortcuts.

**Search** in a toolbar is a 32px field — an input, so it keeps its 1px `line` frame, square
— 200px wide, growing to 280px on focus in 140ms.

```dart
class CfToolbarButton extends StatelessWidget {
  const CfToolbarButton({super.key, required this.icon, this.label, this.active = false, this.onPressed});
  final IconData icon; final String? label; final bool active; final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final fg = active ? CF.onFern : CF.ink;
    return Tooltip(
      message: label ?? '',
      child: Material(
        color: active ? CF.fern : Colors.transparent,
        shape: const RoundedRectangleBorder(
          side: BorderSide.none,
          borderRadius: BorderRadius.zero,
        ),
        child: InkWell(
          onTap: onPressed,
          hoverColor: active ? CF.fernHover : CF.hover,
          borderRadius: BorderRadius.zero,
          child: SizedBox(
            height: 32,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: label == null ? 8 : 11),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 16, color: fg),
                if (label != null) ...[
                  const SizedBox(width: 8),
                  Text(label!, style: Theme.of(context).textTheme.labelLarge!
                      .copyWith(color: fg, fontWeight: FontWeight.w400)),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
```

---

## 9. Dropdown menus

**Surface** — `paper`, 1px `line`, square, level-1 shadow, 6px padding, min-width 180,
max-width 320, max-height 60% of the window with internal scrolling. It opens 4px below its
anchor, left-aligned to it, and flips above when there is no room.

**Items** — 32px tall, square, 10px horizontal padding, label 13px `ink`. Optional 16px
leading icon in `muted` (8px gap). A right-aligned keyboard shortcut in `caption`/`faint`,
tabular. Hover fills the item with `hover`; the keyboard-focused item uses the same wash
plus a 2px `fern` ring inset.

**Checked items** carry a 14px `fern` check in the leading slot — the label does not change
weight. **Destructive items** are `danger` text; on hover they take a `dangerWash` fill.
**Submenus** show a right chevron in `muted` and open on 200ms hover or on `→`.

**Sections** — a 1px `hairline` divider with 6px margins. A section may carry a header:
12px, `muted`, sentence case, 6px padding — **never capitals**.

**Motion** — instant on open and instant on close.

```dart
MenuAnchor(
  style: MenuStyle(
    backgroundColor: const WidgetStatePropertyAll(CF.paper),
    surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
    elevation: const WidgetStatePropertyAll(0),
    padding: const WidgetStatePropertyAll(EdgeInsets.all(6)),
    shape: const WidgetStatePropertyAll(RoundedRectangleBorder(
      side: BorderSide(color: CF.line),
      borderRadius: BorderRadius.zero,
    )),
  ),
  menuChildren: [
    MenuItemButton(
      leadingIcon: const Icon(Icons.check, size: 14, color: CF.fern),
      shortcut: const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
      onPressed: () {},
      child: const Text('New folder'),
    ),
    const Divider(height: 13, thickness: 1, color: CF.hairline),
    MenuItemButton(
      style: MenuItemButton.styleFrom(foregroundColor: CF.danger),
      onPressed: () {},
      child: const Text('Delete'),
    ),
  ],
  builder: (context, controller, child) => CfToolbarButton(
    icon: Icons.more_horiz,
    onPressed: () => controller.isOpen ? controller.close() : controller.open(),
  ),
)
```

For a *value* selector (not commands), use `DropdownMenu<T>` with the same surface styling,
`showTrailingIcon: true`, and `enableFilter: true` above 12 entries.

---

## 10. Bento grid views

Bento is how Cream & Fern displays a **collection of unlike things** — a dashboard, a
project overview, a library home. It is not a replacement for a table.

**Grid** — 12 columns, 12px gutter, 12px outer margin, on the `inset` ground so the tiles
(which are `paper`) separate without shadows. Row height unit 88px; tiles span 1, 2 or 3
units tall.

**Tile** — `paper`, 1px `line`, square, 16px padding, no shadow, no hover lift. A tile
has: a Solway `titleMedium` title, at most **one** primary datum in Instrument Sans 28/500
tabular, and at most **one** fern element (a button, a chip, or a bar) — a tile with two
fern things is over-designed. An optional 12.5px `muted` sub-line carries the timestamp.
Whole-tile click targets get a `hover` wash and a `fern` border on focus.

**Three sanctioned layouts:**

1. **Overview bento** — one hero tile (8 cols × 2 units) with the primary metric or the
   current item, plus four 4×1 satellites down the right and along the bottom. Use for a
   home screen answering "what is happening now?".
2. **Uniform bento** — all tiles 4 cols × 1 unit, wrapping. Use for a gallery, a template
   picker, a plugin list. Add a 3-col variant at ≥1440px.
3. **Rail bento** — a 3-col × 3-unit tall rail on the left holding a list or tree, with a
   9-col region of mixed tiles beside it. Use for a workspace where one axis is navigation.

**Responsive** — 12 cols ≥1280px; 8 cols at 900–1279 (a `4` tile becomes `4`, an `8` tile
becomes `8`, the hero drops to full width); 4 cols below 900, everything full width, hero
first, satellites in source order. Never reflow into a masonry that reorders content.

**Flutter** — prefer first-party `SliverCrossAxisGroup` / `SliverMainAxisGroup` inside one
`CustomScrollView`, or a hand-authored `Row`/`Column` + `Expanded` for fixed layouts.
`flutter_staggered_grid_view` (`SliverQuiltedGridDelegate`) works but is stale (last
published 2023) — treat it as optional.

```dart
// Overview bento, 12-col, gutter 12
LayoutBuilder(builder: (context, c) {
  final cols = c.maxWidth >= 1280 ? 12 : c.maxWidth >= 900 ? 8 : 4;
  double span(int n) => (c.maxWidth - 12 * (cols - 1)) / cols * n + 12 * (n - 1);
  return Wrap(spacing: 12, runSpacing: 12, children: [
    SizedBox(width: span(cols >= 12 ? 8 : cols), height: 188, child: const CfTile(hero: true)),
    SizedBox(width: span(cols >= 12 ? 4 : cols ~/ 2), height: 188, child: const CfTile()),
    for (var i = 0; i < 3; i++)
      SizedBox(width: span(cols >= 12 ? 4 : cols ~/ 2), height: 88, child: const CfTile()),
  ]);
});
```

---

## 11. Lists, tables, and detail panes

- **Table header**: `inset`, 34px, 12.5px `muted` sentence-case labels, 1px `hairline`
  bottom. Sortable columns show a 10px caret in `fern` on the active column only.
- **Rows**: 40px, 1px `hairline` between, `hover` on hover, `fernWash` (not solid fern) when
  selected — solid fern is reserved for navigation, and a table row is not a place.
- **Numeric columns** are right-aligned and tabular; text columns left.
- **Row actions** appear on hover at the right as 28px quiet icon buttons; the destructive
  one is `danger`.
- **Master/detail**: rail 168–220px, list 260–320px, detail flexible. The columns butt
  against each other with no gap; each boundary is a single 1px `line` seam drawn once, not a
  border on both panes. A draggable divider is that same 1px seam with an 8px invisible hit
  area and `SystemMouseCursors.resizeColumn`. Flutter has no first-party splitter — hand-roll it or
  use `multi_split_view`.

---

## 12. Icons and imagery

- **Stroke icons**, 1.6px stroke, rounded caps and joins, on a 20px grid rendered at 16/20/24.
- Icons are `muted` at rest, `ink` when the row is active, `onFern` on fern surfaces.
- **No filled icon set**, no duotone, no emoji as an interface element.
- Illustration and empty-state art: flat shapes in `sage`, `inset`, and `line` with `ink`
  linework — never gradients, never photographs behind text.
- The app mark is a sprite/monogram on `sage` with `onSage` linework, square, 42px.
- Charts: `fern` for the primary series, `sage` and `slate` for others, `hairline` gridlines,
  `muted` axis labels, tabular numerals, and a single emphasised endpoint dot.

---

## 13. Motion, focus, accessibility

- **Durations**: 140ms for hover/color/caret, 180ms for toggles and menu open, 220ms for a
  pane transition. Curve `Curves.easeOut`. Nothing over 240ms.
- **Never animate**: layout width on hover, list reordering, page transitions with slides
  longer than 8px, anything decorative.
- **Focus** is always visible: 2px `fern` ring, 2px offset, square like the control.
  Never remove it, including on mouse users.
- Honour `MediaQuery.disableAnimations` / reduced motion: drop to 0ms, keep end states.
- All interactive text meets 4.5:1; `faint` is disabled-only.
- Every icon-only control has a `Tooltip` **and** a `Semantics` label.
- Keyboard: full tab order, arrow-key navigation inside rails, trees, menus and segmented
  controls; `Esc` closes; `Enter` commits.

---

## 14. Extrapolation rules — when this manual is silent

Apply in order:

1. **Find the nearest sanctioned component** and reuse its geometry (height, border,
   padding) exactly. A new "chip" borrows the menu item's height; its radius, like
   everything else's, is 0.
2. **Snap to the scales.** Any new spacing or size must come from §3, and any radius is 0.
3. **Ask what the colour means.** If the new element is not "where you are" or "this
   commits", it does not get fern. Default to `ink` on `paper`, with a `line` border only if
   it is a nested object rather than a seated region.
4. **Prefer a seam to a gap; prefer a hairline to a fill; prefer a fill to a shadow.**
5. **Give the state a timestamp** if it can go stale.
6. **Name it as the user would.** Controls and headings use the user's noun, not the
   system's — "Notifications", not "Webhook config".
7. **One primary action per surface.**
8. **If in doubt, do less.** A quieter, more spacious version of the sanctioned pattern is
   always the safer extrapolation than a new visual device.

Explicitly permitted liberties: choosing icon glyphs, choosing microcopy within the voice
below, layout of screens not enumerated here, animation of loading skeletons, and the
internal composition of charts — provided §1–§5 hold.

---

## 15. Voice

Sentence case. Active voice. Verbs with objects. State results in the same words as the
action ("Install 1.4.0" → "Installed 1.4.0"). Errors say what happened and what to do, never
apologise, never blame the user. Units and timestamps are spelled ("18.4 MB", "Checked today
at 9:14 AM"). No exclamation marks, no "Oops", no marketing adjectives inside the product.

---

## 16. Implementation checklist

Ship a screen only when all of these are true:

- [ ] No pure white anywhere; every surface is `paper`, `bar`, or `inset`.
- [ ] At most two fern elements on screen, and each is either selection or the primary action.
- [ ] Every header is Solway; every value, label, and number is Instrument Sans.
- [ ] No monospace; every number that lines up uses tabular figures.
- [ ] No ALL-CAPS text.
- [ ] Panes seated and borderless; cards flat, menus shadowed, dialogs scrimmed — no card shadows.
- [ ] Every spacing and height came from §3; every radius is 0, bar a pill toggle or count badge.
- [ ] Nothing rectangular has a rounded corner.
- [ ] Regions meet on one shared 1px `line` seam — no gaps between panes, no doubled borders.
- [ ] Booleans are toggles; 2–4 exclusive options are a framed segmented control; 5+ is a menu.
- [ ] Every stale-able state shows a timestamp.
- [ ] Focus rings visible on every interactive element; icon-only controls have tooltips + semantics.
- [ ] An empty state exists for every list, tree, and grid.
- [ ] Contrast checked against §1.2.

---

## 17. Theme assembly

```dart
ThemeData cfTheme() => ThemeData(
  colorScheme: cfColorScheme,
  scaffoldBackgroundColor: CF.paper,
  canvasColor: CF.paper,
  textTheme: cfTextTheme,
  dividerTheme: const DividerThemeData(color: CF.hairline, thickness: 1, space: 1),
  splashFactory: NoSplash.splashFactory,
  hoverColor: CF.hover,
  focusColor: CF.hover,
  filledButtonTheme: FilledButtonThemeData(style: cfPrimaryButton),
  outlinedButtonTheme: OutlinedButtonThemeData(style: cfSecondaryButton),
  switchTheme: cfSwitchTheme,
  segmentedButtonTheme: cfSegmentedTheme,
  cardTheme: const CardThemeData(
    color: CF.paper, elevation: 0, margin: EdgeInsets.zero,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: CF.line),
      borderRadius: BorderRadius.zero),
  ),
  dialogTheme: const DialogThemeData(
    backgroundColor: CF.paper, elevation: 0, surfaceTintColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: CF.line),
      borderRadius: BorderRadius.zero),
  ),
  tabBarTheme: const TabBarThemeData(
    labelColor: CF.ink, unselectedLabelColor: CF.muted,
    indicatorColor: CF.fern, dividerColor: CF.hairline,
  ),
  tooltipTheme: const TooltipThemeData(
    decoration: BoxDecoration(color: CF.ink,
      borderRadius: BorderRadius.zero),
    textStyle: TextStyle(color: CF.paper, fontSize: 12.5),
    waitDuration: Duration(milliseconds: 400),
  ),
  inputDecorationTheme: InputDecorationThemeData(
    filled: true, fillColor: CF.paper, isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    hintStyle: cfTextTheme.bodyMedium?.copyWith(color: CF.faint),
    border: const OutlineInputBorder(
      borderSide: BorderSide(color: CF.line),
      borderRadius: BorderRadius.zero),
    enabledBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: CF.line),
      borderRadius: BorderRadius.zero),
    focusedBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: CF.fern),
      borderRadius: BorderRadius.zero),
    errorBorder: const OutlineInputBorder(
      borderSide: BorderSide(color: CF.danger),
      borderRadius: BorderRadius.zero),
  ),
  navigationRailTheme: const NavigationRailThemeData(
    backgroundColor: CF.inset,
    indicatorColor: CF.fern,
    selectedIconTheme: IconThemeData(color: CF.onFern, size: 18),
    unselectedIconTheme: IconThemeData(color: CF.muted, size: 18),
  ),
);
```

Use `…ThemeData` classes (`CardThemeData`, `DialogThemeData`, `TabBarThemeData`,
`InputDecorationThemeData`) — the bare `CardTheme`/`DialogTheme`/`TabBarTheme` classes are
now inherited widgets and will not compile in `ThemeData`. Use `WidgetState*`, never the
deprecated `MaterialState*`.

---

## 18. Do not

- Do not add a dark theme, a dark title bar, or a dark sidebar.
- Do not introduce a third typeface, a monospace, or an icon font with letterforms.
- Do not use white, pure black, or any hue outside §1.1.
- Do not put fern on decorative elements, headings, or more than two elements per view.
- Do not use ALL-CAPS, letterspaced labels inside the product.
- Do not add shadows to cards, tiles, table rows, or nav items.
- Do not use gradients, glassmorphism, blur, or a coloured hero.
- Do not use emoji in the interface.
- Do not put a rounded corner on any rectangular surface (the pill toggle and count badge
  are the only exceptions).
- Do not use a gap as a separator between regions, and do not abut two borders where one
  shared seam belongs.
- Do not frame a button other than the primary, or frame a toolbar button.
- Do not animate anything longer than 240ms or with a bounce/elastic curve.
- Do not replace a toggle with a checkbox for a setting, or a checkbox with a toggle for selection.
