/// Application-wide settings and the typography helpers derived from them.
///
/// Two families carry the whole product. **Solway**, a slab serif, labels
/// regions: window titles, pane titles, card titles, section headings. It never
/// carries a value, a sentence of prose, or a control label. **Instrument Sans**
/// carries everything the user actually reads — body copy, control labels,
/// helper text, values, numbers, menu items, buttons, errors.
///
/// There is no monospace anywhere in the product. Version strings, sizes,
/// times, ids and percentages are Instrument Sans with tabular figures;
/// alignment was the only job a monospace was doing.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Application chrome. Pinned, and deliberately not follow[ing] the document
/// font preference: controls, menus and labels keep one voice whatever a
/// document is set in.
const String kUiFontFamily = 'Instrument Sans';

/// Headings in application chrome. Solway labels a region; it never carries a
/// value or a control label.
const String kUiHeaderFontFamily = 'Solway';

/// The default typeface for document content. Unlike [kUiFontFamily] this one
/// is a preference — documents are the user's, and the picker is theirs.
const String kDefaultFontFamily = 'Instrument Sans';

const String _archivoFontFamily = 'Archivo';

/// The anchor for the UI scale: the size at which the configured UI text size
/// equals 100%. It is also the label size in the type scale below.
const double kDefaultUiTextSize = 13;
const double kDefaultEditorTextSize = 15;

/// Fonts offered for document text and suitable as document defaults.
/// Instrument Sans, IBM Plex Sans and Archivo are bundled; the rest are present
/// on macOS and Windows.
const List<String> kAvailableFonts = [
  'Instrument Sans',
  'IBM Plex Sans',
  'Archivo',
  'Georgia',
  'Times New Roman',
  'Helvetica',
  'Arial',
  'Verdana',
];

@immutable
class DsAppSettings {
  const DsAppSettings({
    this.fontFamily = kDefaultFontFamily,
    this.uiTextSize = kDefaultUiTextSize,
    this.editorTextSize = kDefaultEditorTextSize,
  });

  /// The typeface for document content. Application chrome does not follow it.
  final String fontFamily;

  /// The base size for application chrome, controls, menus, and labels.
  final double uiTextSize;

  /// The base size for document titles, prose, headings, tables, and code.
  final double editorTextSize;

  DsAppSettings copyWith({
    String? fontFamily,
    double? uiTextSize,
    double? editorTextSize,
  }) => DsAppSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    uiTextSize: uiTextSize ?? this.uiTextSize,
    editorTextSize: editorTextSize ?? this.editorTextSize,
  );

  @override
  bool operator ==(Object other) =>
      other is DsAppSettings &&
      other.fontFamily == fontFamily &&
      other.uiTextSize == uiTextSize &&
      other.editorTextSize == editorTextSize;

  @override
  int get hashCode => Object.hash(fontFamily, uiTextSize, editorTextSize);
}

/// Owns settings that apply to the whole application and rebuilds the app when
/// any of them changes. Future global settings belong here as new fields on
/// [DsAppSettings], rather than in feature-specific notifiers.
abstract final class DsGlobalSettings {
  static final ValueNotifier<DsAppSettings> _settings = ValueNotifier(
    const DsAppSettings(),
  );

  static DsAppSettings get value => _settings.value;
  static ValueListenable<DsAppSettings> get listenable => _settings;

  static void setFontFamily(String family) {
    final next = family.trim();
    if (next.isEmpty) {
      throw ArgumentError.value(family, 'family', 'must not be empty');
    }
    _settings.value = value.copyWith(fontFamily: next);
  }

  static void setUiTextSize(double size) {
    _validateTextSize(size, 'size');
    _settings.value = value.copyWith(uiTextSize: size);
  }

  static void setEditorTextSize(double size) {
    _validateTextSize(size, 'size');
    _settings.value = value.copyWith(editorTextSize: size);
  }

  static void reset() => _settings.value = const DsAppSettings();

  static void _validateTextSize(double size, String name) {
    if (!size.isFinite || size <= 0) {
      throw ArgumentError.value(
        size,
        name,
        'must be finite and greater than 0',
      );
    }
  }
}

const List<FontFeature> _tabularFigures = [FontFeature.tabularFigures()];

/// Creates a style for application chrome. [size] is the size at the
/// default UI setting and scales proportionally when that setting changes.
///
/// Set [tabular] for any digit the user compares or scans: a column, a
/// right-aligned value, a count, a size, a duration, a percentage.
TextStyle uiTextStyle({
  double size = kDefaultUiTextSize,
  int weight = 400,
  bool italic = false,
  Color? color,
  double? height,
  bool tabular = false,
}) => _textStyle(
  designSize: size,
  configuredSize: DsGlobalSettings.value.uiTextSize,
  defaultSize: kDefaultUiTextSize,
  weight: weight,
  italic: italic,
  color: color,
  height: height,
  tabular: tabular,
  family: kUiFontFamily,
);

/// Creates a style for headings in application chrome.
///
/// Header text follows the global UI size, but keeps Solway whatever the
/// document font is set to. Solway labels a region — it never carries a value.
TextStyle uiHeaderTextStyle({
  double size = 14.5,
  int weight = 500,
  bool italic = false,
  Color? color,
  double? height,
}) => _textStyle(
  designSize: size,
  configuredSize: DsGlobalSettings.value.uiTextSize,
  defaultSize: kDefaultUiTextSize,
  weight: weight,
  italic: italic,
  color: color,
  height: height,
  tabular: false,
  family: kUiHeaderFontFamily,
  letterSpacing: 0.05,
);

/// Creates a style for document content. [size] is the size at the
/// default editor setting and scales proportionally when that setting changes.
TextStyle editorTextStyle({
  double size = kDefaultEditorTextSize,
  int weight = 400,
  bool italic = false,
  Color? color,
  double? height,
  bool tabular = false,
}) => _textStyle(
  designSize: size,
  configuredSize: DsGlobalSettings.value.editorTextSize,
  defaultSize: kDefaultEditorTextSize,
  weight: weight,
  italic: italic,
  color: color,
  height: height,
  tabular: tabular,
);

TextStyle _textStyle({
  required double designSize,
  required double configuredSize,
  required double defaultSize,
  required int weight,
  required bool italic,
  required Color? color,
  required double? height,
  required bool tabular,
  String? family,
  double? letterSpacing,
}) {
  final resolvedFamily = family ?? DsGlobalSettings.value.fontFamily;
  return TextStyle(
    fontFamily: resolvedFamily,
    fontSize: designSize * configuredSize / defaultSize,
    height: height,
    color: color,
    letterSpacing: letterSpacing,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontWeight: _weightOf(weight),
    fontFeatures: tabular ? _tabularFigures : null,
    fontVariations: resolvedFamily == _archivoFontFamily
        ? [FontVariation('wght', weight.toDouble())]
        : null,
  );
}

FontWeight _weightOf(int weight) => switch (weight) {
  <= 300 => FontWeight.w300,
  <= 400 => FontWeight.w400,
  <= 500 => FontWeight.w500,
  <= 600 => FontWeight.w600,
  _ => FontWeight.w700,
};

/// The type scale.
///
/// Sizes and line heights are stated at the default UI text size; every role
/// scales with the user's preference because each is built on [uiTextStyle] or
/// [uiHeaderTextStyle]. Titles are Solway, everything else Instrument Sans —
/// if a value is rendered in Solway, that is a bug.
///
/// Weight 500 is the emphasis weight. Weight 600 is reserved for a page-level
/// headline set in the sans; it does not belong inside dense interface.
abstract final class DsType {
  /// Empty states, onboarding, about. Solway 700.
  static TextStyle display({Color? color}) =>
      uiHeaderTextStyle(size: 34, weight: 700, height: 38 / 34, color: color);

  /// Page heading. Solway 500.
  static TextStyle titleLarge({Color? color}) =>
      uiHeaderTextStyle(size: 22, weight: 500, height: 28 / 22, color: color);

  /// Pane and card titles. Solway 500.
  static TextStyle title({Color? color}) =>
      uiHeaderTextStyle(size: 16, weight: 500, height: 22 / 16, color: color);

  /// Window title bar. Solway 500.
  static TextStyle titleSmall({Color? color}) =>
      uiHeaderTextStyle(size: 14.5, weight: 500, height: 20 / 14.5, color: color);

  /// Prose and dialog body.
  static TextStyle bodyLarge({Color? color}) =>
      uiTextStyle(size: 15, height: 23 / 15, color: color);

  /// Default interface text: list rows, fields, values.
  static TextStyle body({Color? color, bool tabular = false}) =>
      uiTextStyle(size: 13.5, height: 20 / 13.5, color: color, tabular: tabular);

  /// A selected item or a status headline.
  static TextStyle bodyStrong({Color? color, bool tabular = false}) => uiTextStyle(
    size: 13.5,
    weight: 500,
    height: 20 / 13.5,
    color: color,
    tabular: tabular,
  );

  /// Buttons, menu items, tabs.
  static TextStyle label({Color? color, int weight = 400}) =>
      uiTextStyle(size: 13, weight: weight, height: 16 / 13, color: color);

  /// Helper text, timestamps, units.
  static TextStyle caption({Color? color, bool tabular = false}) =>
      uiTextStyle(size: 12.5, height: 17 / 12.5, color: color, tabular: tabular);

  /// Badges, chips, counts.
  static TextStyle micro({Color? color, bool tabular = false}) => uiTextStyle(
    size: 11.5,
    weight: 500,
    height: 14 / 11.5,
    color: color,
    tabular: tabular,
  );
}
