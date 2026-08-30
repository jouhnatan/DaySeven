/// Visual tokens.
///
/// The ground is warm cream, never white. Structure is drawn with hairlines,
/// never with filled bars or heavy chrome. Exactly one saturated colour exists
/// — a deep fern green — and it is spent no more than once or twice per view,
/// on the two things that matter: where you are, and the action that commits.
///
/// There is one palette. The system is light and has no dark variant; a dark
/// title bar, sidebar or footer is not something this interface does. Fern is
/// allowed to be the only dark mass on screen.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/global_settings.dart';

export 'package:dayseven/shared/ui/global_settings.dart';

/// The palette. These values are the system: they are not shifted, tinted or
/// improved in place. Anything that needs a colour takes one of these.
abstract final class CF {
  // Surfaces.
  /// The ground. The default surface for every window, pane, card and sheet.
  static const paper = Color(0xFFFAF7EC);

  /// Only for a surface that floats above [paper] and must separate without a
  /// border. Rare.
  static const paperRaised = Color(0xFFFFFDF6);

  /// Recessed: nav rails, table headers, status blocks, disabled fills.
  static const inset = Color(0xFFF0ECDC);

  /// Title bars and toolbars. Sits between [paper] and [inset].
  static const bar = Color(0xFFEDE9D9);

  // Lines. A hairline divides within one surface; a line is the edge of an
  // object. Nothing else draws structure.
  static const hairline = Color(0xFFE1DBC4);
  static const line = Color(0xFFCFC8AE);

  // Ink.
  static const ink = Color(0xFF1B201A);
  static const muted = Color(0xFF5A6560);

  /// Disabled controls and decorative text only. It measures about 3:1 on
  /// [paper], so a real message never goes in it.
  static const faint = Color(0xFF8A9089);

  // The accent. Selection fill, primary button, toggle-on, focus ring — and
  // nothing else. Fern never means brand decoration; it means *your position*
  // or *this commits*.
  static const fern = Color(0xFF1C3A26);
  static const fernHover = Color(0xFF2A5638);

  /// Fern at 8%, for a selected row in a dense list where a solid block is too
  /// loud.
  static const fernWash = Color(0xFFE9EEE4);

  /// Text and icons on [fern]. A cream, never pure white.
  static const onFern = Color(0xFFF7F4E9);

  // Decorative and informational.
  static const sage = Color(0xFFB7CDB6);
  static const onSage = Color(0xFF2A4433);

  /// Links and informational accents. The cool voice.
  static const slate = Color(0xFF3E5A56);

  // Semantic. These describe state; they are not accents, and they appear as
  // text plus a small mark rather than as a filled block.
  static const success = Color(0xFF3A6E4C);
  static const warning = Color(0xFF8A6A18);
  static const warningWash = Color(0xFFF2E7C4);
  static const danger = Color(0xFF7A3327);
  static const dangerWash = Color(0xFFF3E3DC);

  // Washes.
  static const hover = Color(0x0F1B201A); // 6%
  static const pressed = Color(0x1A1B201A); // 10%
  static const scrim = Color(0x660E120C); // 40%
}

/// The semantic roles the interface reads through, as [BuildContext.ds].
///
/// Roles name what a colour *means* here, so a widget asks for the editor
/// surface rather than for cream. There is one instance: [DsColors.cream].
class DsColors extends ThemeExtension<DsColors> {
  const DsColors();

  /// The one palette.
  static const cream = DsColors();

  /// The window background. Everything else sits on top of it. Islands are
  /// [paper] on this recessed ground, which is what lets the gaps between them
  /// read as separation without a border or a shadow.
  Color get appBackground => CF.inset;

  /// Side-menu islands and bottom-bar buttons.
  Color get island => CF.paper;

  /// The editing canvas.
  Color get editorSurface => CF.paper;

  /// A contrasting section nested inside an island and separated by a line.
  Color get cardSurface => CF.inset;

  /// The edge of an object: an island, a button, a field, a card.
  Color get surfaceOutline => CF.line;

  /// Structural lines inside surfaces: dividers, fields, and tree details.
  Color get border => CF.hairline;

  Color get text => CF.ink;
  Color get muted => CF.muted;

  /// Disabled text. Never anything actionable.
  Color get faint => CF.faint;

  /// Title bars and toolbars.
  Color get bar => CF.bar;

  // The accent, and what sits on it.
  Color get fern => CF.fern;
  Color get fernHover => CF.fernHover;
  Color get onFern => CF.onFern;

  /// Where you are: a nav item, a selected tree row. A solid fern block with
  /// [onFern] text. Position is shown by fill, not by weight.
  Color get navSelected => CF.fern;
  Color get onNavSelected => CF.onFern;

  /// A selected row in a dense list or table, where a solid block would be too
  /// loud. Solid fern is reserved for navigation, and a table row is not a
  /// place.
  Color get rowSelected => CF.fernWash;

  /// A recessed wash: a table header, a code block, an image placeholder, and
  /// the hover fill of a framed button. It is a surface that has sunk, not a
  /// selection — where you are is [navSelected].
  Color get selection => CF.inset;

  /// The universal hover wash, over any surface.
  Color get hover => CF.hover;
  Color get pressed => CF.pressed;

  /// Behind modals.
  Color get scrim => CF.scrim;

  /// The wash behind the paragraph being edited. It marks where typing is
  /// going, which the caret alone does not do well in a page of evenly spaced
  /// blocks.
  Color get editingBlock => CF.fernWash;

  /// Link text.
  Color get link => CF.slate;

  /// Attention, not failure: a proposal waiting, a check overdue.
  Color get pending => CF.warning;

  // Decorative: the app mark, avatar fills, illustration.
  Color get sage => CF.sage;
  Color get onSage => CF.onSage;

  /// Positive state: up to date, saved, synced.
  Color get success => CF.success;

  /// Destructive action and error state.
  Color get danger => CF.danger;

  // Diff view only.
  Color get addition => CF.fernWash;
  Color get removal => CF.dangerWash;
  Color get conflict => CF.warningWash;

  @override
  DsColors copyWith() => this;

  @override
  DsColors lerp(ThemeExtension<DsColors>? other, double t) =>
      t < 0.5 ? this : (other as DsColors? ?? this);
}

/// Corner radii. Nothing is larger than 10 except a pill toggle.
class DsRadius {
  /// Table cells, full-bleed rows, dividers.
  static const none = Radius.zero;

  /// Nav items, menu items, chips, small icon buttons.
  static const row = Radius.circular(6);

  /// The wash behind the paragraph being edited.
  static const block = Radius.circular(6);

  /// Menu items.
  static const menuItem = Radius.circular(6);

  /// Buttons, inputs, toolbar buttons.
  static const control = Radius.circular(7);

  /// Segmented controls, status blocks, menus, popovers.
  static const menu = Radius.circular(8);

  /// Cards, tiles, dialogs, windows.
  static const island = Radius.circular(10);

  /// Toggle track and thumb only.
  static const pill = Radius.circular(999);
}

/// Collaborator colours.
///
/// One per person, picked by hashing their user id so that somebody is the
/// same colour on both machines. These sit outside the palette on purpose:
/// they encode identity rather than meaning, and there are more of them than
/// the system has colours. They are mid-tone hues chosen to hold against
/// [CF.paper] and against a [CF.fern] selection without going neon.
class DsPresence {
  const DsPresence._();

  static const palette = <Color>[
    Color(0xFF3E6FA8), // blue
    Color(0xFF9A5B22), // amber
    Color(0xFF3A6E4C), // green
    Color(0xFF7A4F94), // violet
    Color(0xFF9C4550), // rose
    Color(0xFF2A7076), // teal
  ];

  /// The dot size in the tree and the toolbar.
  static const dotSize = 14.0;

  /// How far each dot in a stack overlaps the one before it.
  static const dotOverlap = 4.0;

  /// The width of the bar drawn beside a block a collaborator is in.
  static const blockMarkerWidth = 2.0;
}

/// Palette colors for Timeline milestone items and period spans.
enum TimelineColor {
  fern('fern', 'Fern', Color(0xFF1C3A26)),
  blue('blue', 'Sapphire', Color(0xFF3E6FA8)),
  amber('amber', 'Amber', Color(0xFF9A5B22)),
  green('green', 'Emerald', Color(0xFF3A6E4C)),
  violet('violet', 'Violet', Color(0xFF7A4F94)),
  rose('rose', 'Rose', Color(0xFF9C4550)),
  teal('teal', 'Teal', Color(0xFF2A7076)),
  slate('slate', 'Slate', Color(0xFF3E5A56));

  const TimelineColor(this.id, this.label, this.color);

  final String id;
  final String label;
  final Color color;

  static TimelineColor fromId(String? id) {
    if (id == null) return TimelineColor.fern;
    final clean = id.toLowerCase().trim();
    return TimelineColor.values.firstWhere(
      (c) => c.id == clean,
      orElse: () => TimelineColor.fern,
    );
  }
}

/// Spacing, on a 4pt base. A value outside this scale is not invented.
class DsSpace {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const s = 8.0;

  /// The gap that separates the island from the editor.
  static const islandGap = 10.0;
  static const pane = 12.0;
  static const sm = 12.0;
  static const row = 6.0;
  static const controlGap = 6.0;
  static const m = 16.0;
  static const blockBefore = 16.0;
  static const ml = 20.0;
  static const l = 24.0;
  static const xl = 32.0;
  static const xxl = 40.0;
}

/// Control heights, at the desktop density this application targets.
class DsSize {
  /// Primary and secondary buttons, and text inputs.
  static const control = 36.0;

  /// Small buttons, toolbar buttons, icon-only buttons.
  static const smallControl = 32.0;

  /// Menu items.
  static const menuItem = 32.0;

  /// A list or table row.
  static const listRow = 40.0;

  /// A dense list row, and a tree row.
  static const denseRow = 26.0;

  /// The focus ring: 2px, offset 2px. Nothing else is 2px.
  static const focusRing = 2.0;
  static const focusRingOffset = 2.0;
}

/// Motion is functional and short. Colour, background and small transforms
/// only — nothing bounces and nothing parallaxes.
class DsMotion {
  static const hover = Duration(milliseconds: 140);
  static const toggle = Duration(milliseconds: 180);
  static const pane = Duration(milliseconds: 220);
  static const curve = Curves.easeOut;

  /// Honours the platform's reduced-motion setting by dropping to no duration
  /// while keeping the end state.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : duration;
}

/// Depth comes from borders, not shadows. There are four levels: flat panes
/// and cards carry a border and no shadow at all; only things that float above
/// the page are allowed one.
const cfMenuShadow = <BoxShadow>[
  BoxShadow(color: Color(0x0F1B201A), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(
    color: Color(0x381B201A),
    blurRadius: 20,
    spreadRadius: -10,
    offset: Offset(0, 8),
  ),
];

/// The chosen cell of a segmented control, raised out of its frame.
const cfSegmentedShadow = <BoxShadow>[
  BoxShadow(color: Color(0x141B201A), blurRadius: 1, offset: Offset(0, 1)),
  BoxShadow(color: Color(0x0F1B201A), blurRadius: 2, offset: Offset(0, 2)),
];

const cfWindowShadow = <BoxShadow>[
  BoxShadow(color: Color(0x141B201A), blurRadius: 2, offset: Offset(0, 1)),
  BoxShadow(
    color: Color(0x4D1B201A),
    blurRadius: 36,
    spreadRadius: -14,
    offset: Offset(0, 14),
  ),
];

/// Every Material role, stated rather than derived. A generated scheme would
/// tint these off a seed and put colours on screen that are not in the palette.
const cfColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: CF.fern,
  onPrimary: CF.onFern,
  primaryContainer: CF.fernWash,
  onPrimaryContainer: CF.fern,
  secondary: CF.slate,
  onSecondary: CF.paper,
  secondaryContainer: CF.inset,
  onSecondaryContainer: CF.ink,
  tertiary: CF.sage,
  onTertiary: CF.onSage,
  error: CF.danger,
  onError: CF.paper,
  errorContainer: CF.dangerWash,
  onErrorContainer: CF.ink,
  surface: CF.paper,
  onSurface: CF.ink,
  surfaceDim: CF.inset,
  surfaceBright: CF.paperRaised,
  surfaceContainerLowest: CF.paperRaised,
  surfaceContainerLow: CF.paper,
  surfaceContainer: CF.bar,
  surfaceContainerHigh: CF.inset,
  surfaceContainerHighest: CF.inset,
  onSurfaceVariant: CF.muted,
  outline: CF.line,
  outlineVariant: CF.hairline,
  shadow: CF.ink,
  scrim: CF.scrim,
  inverseSurface: CF.fern,
  onInverseSurface: CF.onFern,
  inversePrimary: CF.sage,
);

ThemeData dsTheme({DsAppSettings? settings}) {
  const c = DsColors.cream;
  final appSettings = settings ?? DsGlobalSettings.value;
  final uiTextScale = appSettings.uiTextSize / kDefaultUiTextSize;

  return ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: c.appBackground,
    canvasColor: c.appBackground,
    // Chrome keeps its own face whatever a document is set in.
    fontFamily: kUiFontFamily,
    colorScheme: cfColorScheme,
    dividerColor: c.border,
    textTheme: _cfTextTheme(uiTextScale),
    extensions: const [c],
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.hover,
    focusColor: c.hover,
    dividerTheme: DividerThemeData(
      color: c.border,
      thickness: 1,
      space: 1,
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.pressed)) return c.pressed;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused)) {
            return c.hover;
          }
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: CF.fern,
        foregroundColor: CF.onFern,
        disabledBackgroundColor: CF.inset,
        disabledForegroundColor: CF.faint,
        minimumSize: const Size(0, DsSize.control),
        padding: const EdgeInsets.symmetric(horizontal: 17),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(DsRadius.control),
        ),
      ).copyWith(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? CF.inset
              : s.contains(WidgetState.hovered) ||
                    s.contains(WidgetState.pressed)
              ? CF.fernHover
              : CF.fern,
        ),
        textStyle: WidgetStatePropertyAll(DsType.label(weight: 500)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        backgroundColor: CF.paper,
        foregroundColor: CF.ink,
        side: const BorderSide(color: CF.line),
        minimumSize: const Size(0, DsSize.control),
        padding: const EdgeInsets.symmetric(horizontal: 15),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(DsRadius.control),
        ),
      ).copyWith(textStyle: WidgetStatePropertyAll(DsType.label())),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled)
            ? CF.hairline
            : s.contains(WidgetState.selected)
            ? CF.fern
            : CF.line,
      ),
      thumbColor: const WidgetStatePropertyAll(CF.paper),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackOutlineWidth: const WidgetStatePropertyAll(0),
      overlayColor: const WidgetStatePropertyAll(CF.hover),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? CF.paper : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? CF.ink : CF.muted,
        ),
        textStyle: WidgetStatePropertyAll(DsType.caption()),
        side: const WidgetStatePropertyAll(BorderSide.none),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(DsRadius.row)),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 13),
        ),
        minimumSize: const WidgetStatePropertyAll(Size(0, 30)),
      ),
    ),
    cardTheme: const CardThemeData(
      color: CF.paper,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: CF.line),
        borderRadius: BorderRadius.all(DsRadius.island),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: CF.paper,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      barrierColor: CF.scrim,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: CF.line),
        borderRadius: BorderRadius.all(DsRadius.island),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: CF.ink,
      unselectedLabelColor: CF.muted,
      indicatorColor: CF.fern,
      dividerColor: CF.hairline,
    ),
    tooltipTheme: TooltipThemeData(
      // The one place ink is used as a surface.
      decoration: const BoxDecoration(
        color: CF.ink,
        borderRadius: BorderRadius.all(DsRadius.row),
      ),
      textStyle: DsType.caption(color: CF.paper),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      waitDuration: const Duration(milliseconds: 400),
    ),
    // Deliberately neutral. Fields in this application paint their own box —
    // see DsField — and a theme-level border would win over a field that has
    // explicitly asked for none, because Flutter resolves enabledBorder and
    // focusedBorder from the theme before falling back to the field's own
    // `border`. Setting them here put an outline around every paragraph in
    // the editor. The geometry a field is meant to have lives in DsField.
    inputDecorationTheme: InputDecorationThemeData(
      filled: false,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      hintStyle: DsType.body(color: CF.faint),
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      errorStyle: DsType.caption(color: CF.danger),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: CF.fern,
      linearTrackColor: CF.inset,
      circularTrackColor: CF.inset,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: CF.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      textStyle: DsType.label(),
      shape: const RoundedRectangleBorder(
        side: BorderSide(color: CF.line),
        borderRadius: BorderRadius.all(DsRadius.menu),
      ),
    ),
    iconTheme: const IconThemeData(color: CF.muted, size: 16),
  );
}

/// Titles are Solway, everything else Instrument Sans. The scale is stated at
/// the default UI size and multiplied by the user's preference.
TextTheme _cfTextTheme(double scale) {
  TextStyle at(TextStyle style) =>
      style.copyWith(fontSize: (style.fontSize ?? kDefaultUiTextSize) * scale);

  return TextTheme(
    displayLarge: at(DsType.display()),
    displayMedium: at(uiHeaderTextStyle(size: 28, weight: 700, height: 34 / 28)),
    displaySmall: at(uiHeaderTextStyle(size: 24, weight: 700, height: 30 / 24)),
    headlineLarge: at(DsType.titleLarge()),
    headlineMedium: at(uiHeaderTextStyle(size: 19, height: 25 / 19)),
    headlineSmall: at(DsType.title()),
    titleLarge: at(DsType.title()),
    titleMedium: at(DsType.titleSmall()),
    titleSmall: at(DsType.label(weight: 500)),
    bodyLarge: at(DsType.bodyLarge()),
    bodyMedium: at(DsType.body()),
    bodySmall: at(DsType.caption(color: CF.muted)),
    labelLarge: at(DsType.label(weight: 500)),
    labelMedium: at(DsType.caption()),
    labelSmall: at(DsType.micro()),
  );
}

extension DsThemeAccess on BuildContext {
  DsColors get ds => Theme.of(this).extension<DsColors>()!;
}
