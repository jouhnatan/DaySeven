/// Visual tokens.
///
/// Three surface tones, each a subtle step apart: the application background,
/// the island/panel, and the editor surface. Flat — no gradients, no shadows
/// beyond a hairline border, and one coloured fill: the paragraph being edited.
/// Follows the system light/dark setting, which adds no control to the
/// interface.
library;

import 'package:flutter/material.dart';

const String kEditorFontFamily = 'Aleo';

/// Fonts offered by the font selector. Aleo is bundled; the rest are the
/// families present on both macOS and Windows.
const List<String> kAvailableFonts = [
  'Aleo',
  'Georgia',
  'Times New Roman',
  'Helvetica',
  'Arial',
  'Courier New',
  'Verdana',
];

class DsColors extends ThemeExtension<DsColors> {
  const DsColors({
    required this.appBackground,
    required this.island,
    required this.editorSurface,
    required this.border,
    required this.text,
    required this.muted,
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

  /// The right-hand Knowledge Base island and the bottom bar button.
  final Color island;

  /// The editing canvas.
  final Color editorSurface;

  final Color border;
  final Color text;
  final Color muted;

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
    editorSurface: Color(0xFF17191D),
    border: Color(0xFF2A2D34),
    text: Color(0xFFD6D9DF),
    muted: Color(0xFF868D99),
    selection: Color(0xFF23262D),
    editingBlock: Color(0xFF1A1F2B),
    link: Color(0xFF7FA6D8),
    pending: Color(0xFFC8A45C),
    addition: Color(0xFF1E2A22),
    removal: Color(0xFF2A1E20),
    conflict: Color(0xFF2C2718),
  );

  static const light = DsColors(
    appBackground: Color(0xFFE8E9EC),
    island: Color(0xFFF4F5F7),
    editorSurface: Color(0xFFFBFBFC),
    border: Color(0xFFD8DAE0),
    text: Color(0xFF1D2025),
    muted: Color(0xFF6B7280),
    selection: Color(0xFFE3E5EA),
    editingBlock: Color(0xFFEFF3FC),
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

  /// The wash behind the paragraph being edited.
  static const block = Radius.circular(5);
}

class DsSpace {
  /// The gap that separates the island from the editor.
  static const islandGap = 10.0;
  static const pane = 12.0;
  static const row = 6.0;
}

ThemeData dsTheme(Brightness brightness) {
  final c = brightness == Brightness.dark ? DsColors.dark : DsColors.light;

  return ThemeData(
    brightness: brightness,
    scaffoldBackgroundColor: c.appBackground,
    canvasColor: c.appBackground,
    fontFamily: kEditorFontFamily,
    colorScheme: ColorScheme.fromSeed(
      seedColor: c.island,
      brightness: brightness,
      surface: c.island,
    ).copyWith(onSurface: c.text),
    dividerColor: c.border,
    textTheme: Typography.material2021(platform: TargetPlatform.macOS).black
        .apply(
          fontFamily: kEditorFontFamily,
          bodyColor: c.text,
          displayColor: c.text,
        ),
    extensions: [c],
    visualDensity: VisualDensity.compact,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}

extension DsThemeAccess on BuildContext {
  DsColors get ds => Theme.of(this).extension<DsColors>()!;
}

/// Aleo is a variable font: weight comes from the `wght` axis rather than from
/// separate static files, so every weighted style must set a FontVariation.
TextStyle aleo({
  double size = 15,
  int weight = 400,
  bool italic = false,
  Color? color,
  double? height,
}) => TextStyle(
  fontFamily: kEditorFontFamily,
  fontSize: size,
  height: height,
  color: color,
  fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  fontWeight: _weightOf(weight),
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

FontWeight _weightOf(int w) => switch (w) {
  <= 300 => FontWeight.w300,
  <= 400 => FontWeight.w400,
  <= 500 => FontWeight.w500,
  <= 600 => FontWeight.w600,
  _ => FontWeight.w700,
};
