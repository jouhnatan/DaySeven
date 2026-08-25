/// Visual tokens.
///
/// Shared light/dark color tokens for the window, pane/editor surfaces, and
/// darker Cards nested inside islands.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/global_settings.dart';

export 'package:dayseven/shared/ui/global_settings.dart';

class DsColors extends ThemeExtension<DsColors> {
  const DsColors({
    required this.appBackground,
    required this.island,
    required this.editorSurface,
    required this.cardSurface,
    required this.surfaceOutline,
    required this.border,
    required this.text,
    required this.muted,
    required this.buttonHighlight,
    required this.selection,
    required this.editingBlock,
    required this.link,
    required this.pending,
    required this.addition,
    required this.removal,
    required this.conflict,
  });

  /// The window background. Everything else sits on top of it.
  final Color appBackground;

  /// Side-menu islands and bottom-bar buttons.
  final Color island;

  /// The editing canvas.
  final Color editorSurface;

  /// A contrasting section nested inside an island and separated by a line.
  /// In the light theme this is the standardized darker Card white.
  final Color cardSurface;

  /// The slightly darker hairline around islands and shared buttons.
  final Color surfaceOutline;

  /// Structural lines inside surfaces: dividers, fields, and tree details.
  final Color border;
  final Color text;
  final Color muted;

  /// The green wash behind actionable buttons while hovered or active.
  final Color buttonHighlight;

  /// Row hover/selection wash in lists and the tree.
  final Color selection;

  /// The wash behind the paragraph being edited. The one coloured fill in the
  /// interface: it marks where typing is going, which the caret alone does not
  /// do well in a page of evenly spaced blocks.
  final Color editingBlock;

  /// Link text. The one place the interface uses colour to mean something
  /// rather than to decorate.
  final Color link;

  /// The dot on the Differences button when a proposal is waiting.
  final Color pending;

  /// Diff view only.
  final Color addition;
  final Color removal;
  final Color conflict;

  static const dark = DsColors(
    appBackground: Color(0xFF121317),
    island: Color(0xFF1C1E23),
    editorSurface: Color(0xFF1C1E23),
    cardSurface: Color(0xFF14161B),
    surfaceOutline: Color(0xFF101216),
    border: Color(0xFF2A2D34),
    text: Color(0xFFD6D9DF),
    muted: Color(0xFF868D99),
    buttonHighlight: Color(0xFF416750),
    selection: Color(0xFF23262D),
    editingBlock: Color(0xFF2C4637),
    link: Color(0xFF7FA6D8),
    pending: Color(0xFFC8A45C),
    addition: Color(0xFF1E2A22),
    removal: Color(0xFF2A1E20),
    conflict: Color(0xFF2C2718),
  );

  static const light = DsColors(
    appBackground: Color(0xFFE8E9EC),
    island: Color(0xFFFBFBFC),
    editorSurface: Color(0xFFFBFBFC),
    cardSurface: Color(0xFFE9EAED),
    surfaceOutline: Color(0xFFA7ACB6),
    border: Color(0xFFC3C6CE),
    text: Color(0xFF1D2025),
    muted: Color(0xFF6B7280),
    buttonHighlight: Color(0xFFC6D9C9),
    selection: Color(0xFFE3E5EA),
    editingBlock: Color(0xFFE4F1E7),
    link: Color(0xFF1F5FA8),
    pending: Color(0xFF9A7526),
    addition: Color(0xFFE7F1E9),
    removal: Color(0xFFF6E8E9),
    conflict: Color(0xFFF6EFD9),
  );

  @override
  DsColors copyWith() => this;

  @override
  DsColors lerp(ThemeExtension<DsColors>? other, double t) =>
      t < 0.5 ? this : (other as DsColors? ?? this);
}

/// Corner radii. Rounded, but only where the interface is specified to be.
class DsRadius {
  static const island = Radius.circular(10);
  static const control = Radius.circular(8);
  static const row = Radius.circular(6);
  static const menuItem = Radius.circular(9);

  /// The wash behind the paragraph being edited.
  static const block = Radius.circular(5);
}

/// Collaborator colours.
///
/// One per person, picked by hashing their user id so that somebody is the
/// same colour on both machines. Presence dots are small and sit on the island
/// and the editor surface in both themes, so these are mid-tone hues that hold
/// their identity against either without going neon.
class DsPresence {
  const DsPresence._();

  static const palette = <Color>[
    Color(0xFF4E8FCF), // blue
    Color(0xFFC97B3C), // amber
    Color(0xFF57A177), // green
    Color(0xFFA972C4), // violet
    Color(0xFFCB6A72), // rose
    Color(0xFF3FA0A6), // teal
  ];

  /// The dot size in the tree and the toolbar.
  static const dotSize = 14.0;

  /// How far each dot in a stack overlaps the one before it.
  static const dotOverlap = 4.0;

  /// The width of the bar drawn beside a block a collaborator is in.
  static const blockMarkerWidth = 2.0;
}

class DsSpace {
  /// The gap that separates the island from the editor.
  static const islandGap = 10.0;
  static const pane = 12.0;
  static const row = 6.0;
  static const controlGap = 6.0;
  static const blockBefore = 16.0;
}

class DsMotion {
  static const hover = Duration(milliseconds: 90);
  static const pane = Duration(milliseconds: 200);
}

ThemeData dsTheme(Brightness brightness, {DsAppSettings? settings}) {
  final c = brightness == Brightness.dark ? DsColors.dark : DsColors.light;
  final appSettings = settings ?? DsGlobalSettings.value;
  final uiTextScale = appSettings.uiTextSize / kDefaultUiTextSize;

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.appBackground,
    canvasColor: c.appBackground,
    fontFamily: appSettings.fontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.island,
      brightness: brightness,
      surface: c.island,
    ).copyWith(onSurface: c.text),
    dividerColor: c.border,
    textTheme: _scaleTextTheme(
      Typography.material2021(platform: TargetPlatform.macOS).black.apply(
        fontFamily: appSettings.fontFamily,
        bodyColor: c.text,
        displayColor: c.text,
      ),
      uiTextScale,
    ),
    extensions: [c],
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.disabled)) return Colors.transparent;
          if (states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.focused) ||
              states.contains(WidgetState.pressed)) {
            return c.buttonHighlight;
          }
          return Colors.transparent;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
  );
}

/// [TextTheme.apply] asserts when asked to scale an inherited style whose
/// font size is null. Material includes a few such styles, so scale only the
/// roles that define a concrete size and leave inherited sizes untouched.
TextTheme _scaleTextTheme(TextTheme theme, double factor) {
  TextStyle? scale(TextStyle? style) {
    final size = style?.fontSize;
    return size == null ? style : style!.copyWith(fontSize: size * factor);
  }

  return theme.copyWith(
    displayLarge: scale(theme.displayLarge),
    displayMedium: scale(theme.displayMedium),
    displaySmall: scale(theme.displaySmall),
    headlineLarge: scale(theme.headlineLarge),
    headlineMedium: scale(theme.headlineMedium),
    headlineSmall: scale(theme.headlineSmall),
    titleLarge: scale(theme.titleLarge),
    titleMedium: scale(theme.titleMedium),
    titleSmall: scale(theme.titleSmall),
    bodyLarge: scale(theme.bodyLarge),
    bodyMedium: scale(theme.bodyMedium),
    bodySmall: scale(theme.bodySmall),
    labelLarge: scale(theme.labelLarge),
    labelMedium: scale(theme.labelMedium),
    labelSmall: scale(theme.labelSmall),
  );
}

extension DsThemeAccess on BuildContext {
  DsColors get ds => Theme.of(this).extension<DsColors>()!;
}
