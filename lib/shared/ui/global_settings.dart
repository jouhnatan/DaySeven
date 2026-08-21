/// Application-wide settings and the typography helpers derived from them.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const String kDefaultFontFamily = 'IBM Plex Sans';
const String kUiHeaderFontFamily = 'Geist Pixel Square';
const String _archivoFontFamily = 'Archivo';
const double kDefaultUiTextSize = 13;
const double kDefaultEditorTextSize = 15;

/// Fonts offered by the editor and suitable as application defaults. IBM Plex
/// Sans and Archivo are bundled; the rest are present on macOS and Windows.
const List<String> kAvailableFonts = [
  'IBM Plex Sans',
  'Archivo',
  'Georgia',
  'Times New Roman',
  'Helvetica',
  'Arial',
  'Courier New',
  'Verdana',
];

@immutable
class DsAppSettings {
  const DsAppSettings({
    this.fontFamily = kDefaultFontFamily,
    this.uiTextSize = kDefaultUiTextSize,
    this.editorTextSize = kDefaultEditorTextSize,
    this.gradientBackgroundEnabled = false,
  });

  final String fontFamily;

  /// The base size for application chrome, controls, menus, and labels.
  final double uiTextSize;

  /// The base size for document titles, prose, headings, tables, and code.
  final double editorTextSize;

  /// Whether the gradient also fills the outer background of non-Home views.
  /// Home always uses the gradient; pane and editor surfaces stay opaque.
  final bool gradientBackgroundEnabled;

  DsAppSettings copyWith({
    String? fontFamily,
    double? uiTextSize,
    double? editorTextSize,
    bool? gradientBackgroundEnabled,
  }) => DsAppSettings(
    fontFamily: fontFamily ?? this.fontFamily,
    uiTextSize: uiTextSize ?? this.uiTextSize,
    editorTextSize: editorTextSize ?? this.editorTextSize,
    gradientBackgroundEnabled:
        gradientBackgroundEnabled ?? this.gradientBackgroundEnabled,
  );

  @override
  bool operator ==(Object other) =>
      other is DsAppSettings &&
      other.fontFamily == fontFamily &&
      other.uiTextSize == uiTextSize &&
      other.editorTextSize == editorTextSize &&
      other.gradientBackgroundEnabled == gradientBackgroundEnabled;

  @override
  int get hashCode => Object.hash(
    fontFamily,
    uiTextSize,
    editorTextSize,
    gradientBackgroundEnabled,
  );
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

  static void setGradientBackgroundEnabled(bool enabled) {
    _settings.value = value.copyWith(gradientBackgroundEnabled: enabled);
  }

  static void toggleGradientBackground() {
    setGradientBackgroundEnabled(!value.gradientBackgroundEnabled);
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

/// Creates a style for application chrome. [size] is the size at the
/// default UI setting and scales proportionally when that setting changes.
TextStyle uiTextStyle({
  double size = kDefaultUiTextSize,
  int weight = 400,
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
);

/// Creates a style for headings in application chrome.
///
/// Header text follows the global UI size, but deliberately keeps its own
/// bundled display family when the body/editor family is changed.
TextStyle uiHeaderTextStyle({
  double size = 14,
  int weight = 400,
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
  family: kUiHeaderFontFamily,
);

/// Creates a style for document content. [size] is the size at the
/// default editor setting and scales proportionally when that setting changes.
TextStyle editorTextStyle({
  double size = kDefaultEditorTextSize,
  int weight = 400,
  bool italic = false,
  Color? color,
  double? height,
}) => _textStyle(
  designSize: size,
  configuredSize: DsGlobalSettings.value.editorTextSize,
  defaultSize: kDefaultEditorTextSize,
  weight: weight,
  italic: italic,
  color: color,
  height: height,
);

TextStyle _textStyle({
  required double designSize,
  required double configuredSize,
  required double defaultSize,
  required int weight,
  required bool italic,
  required Color? color,
  required double? height,
  String? family,
}) {
  final resolvedFamily = family ?? DsGlobalSettings.value.fontFamily;
  return TextStyle(
    fontFamily: resolvedFamily,
    fontSize: designSize * configuredSize / defaultSize,
    height: height,
    color: color,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
    fontWeight: _weightOf(weight),
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
