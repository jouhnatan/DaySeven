/// The App settings dialog's own palette and type scale.
///
/// This is a second, smaller design system living beside the application's, and
/// that is deliberate rather than accidental: App settings follows a specific
/// flat-and-grained design with its own paper, its own green, and three
/// typefaces the rest of DaySeven does not use.
///
/// Nothing outside `features/app_settings/` should import this. If a value here
/// starts being wanted elsewhere, it belongs in `shared/ui/theme.dart` as a
/// real theme token instead, where it can answer to light and dark.
///
/// The palette has no dark variant, so the dialog stays light whatever the rest
/// of the window is doing.
library;

import 'package:flutter/widgets.dart';

import 'package:dayseven/shared/ui/theme.dart';

/// Flat, opaque fills — no gradients anywhere in this design.
abstract final class AppSettingsPalette {
  /// The page itself, and the fill of rows sitting on [paperHi].
  static const paper = Color(0xFFD9D9D9);

  /// The dialog surface, a shade up from the rows it holds.
  static const paperHi = Color(0xFFE4E4E2);

  /// The footer bar, a shade down.
  static const paperLo = Color(0xFFCDCDCB);

  static const ink = Color(0xFF1E1E1E);
  static const ink60 = Color(0xFF5A5A58);
  static const ink40 = Color(0xFF87877F);

  /// The header block.
  static const charcoal = Color(0xFF2B2B29);

  /// Buttons, section headings, and the status marker.
  static const green = Color(0xFF0E3721);
  static const greenHover = Color(0xFF154429);
  static const greenActive = Color(0xFF0A2B19);

  /// The green flattened into the paper, for tinted rows and pale plates.
  static const greenTint = Color(0xFFC3CEC5);
  static const greenTint2 = Color(0xFFAFBFB2);

  static const red = Color(0xFF6B1712);
  static const redHover = Color(0xFF84201A);
  static const redTint = Color(0xFFD2C4C1);

  /// The ink flattened into the paper, for a neutral tinted row.
  static const inkTint = Color(0xFFC6C6C4);

  /// The single hairline this design uses in place of shadows.
  static const rule = Color(0xFFB4B4B2);
}

/// The design's type scale, at the application's default text size.
///
/// These are the sizes the design specifies. They are not literal at render
/// time — see [_scaled].
abstract final class AppSettingsType {
  static const title = 22.0;
  static const heading = 17.0;
  static const body = 15.0;
  static const sub = 13.0;
  static const micro = 10.0;
}

const _display = 'Solway';
const _body = 'Space Grotesk';
const _meta = 'Figtree';

/// Scales a design size by whatever the person has set the UI text size to.
///
/// The design specifies fixed sizes, and honouring them literally would mean
/// one dialog in the application that ignores a preference every other surface
/// respects. Applying the same ratio `uiTextStyle` applies keeps the design
/// exact at the default setting and legible away from it.
double _scaled(double size) =>
    size * DsGlobalSettings.value.uiTextSize / kDefaultUiTextSize;

/// Solway. Titles and the bold first line of a row.
TextStyle appSettingsDisplay({
  double size = AppSettingsType.body,
  FontWeight weight = FontWeight.w700,
  Color color = AppSettingsPalette.ink,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: _display,
  fontSize: _scaled(size),
  fontWeight: weight,
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

/// Space Grotesk. Paragraphs, buttons, and everything unremarkable.
TextStyle appSettingsBody({
  double size = AppSettingsType.body,
  FontWeight weight = FontWeight.w400,
  Color color = AppSettingsPalette.ink,
  double? height,
  double? letterSpacing,
}) => TextStyle(
  fontFamily: _body,
  fontSize: _scaled(size),
  fontWeight: weight,
  // Space Grotesk is variable on the weight axis, so the weight has to be set
  // on the axis as well as declared — the same arrangement Archivo uses in
  // shared/ui/global_settings.dart.
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
  height: height,
  letterSpacing: letterSpacing,
);

/// Figtree. The second line of a row — a version, a build, a short status.
///
/// Figtree's default instance is Light, so the weight is always stated on the
/// axis rather than left to the file.
TextStyle appSettingsMeta({
  double size = AppSettingsType.sub,
  FontWeight weight = FontWeight.w400,
  Color color = AppSettingsPalette.ink40,
  double? height,
}) => TextStyle(
  fontFamily: _meta,
  fontSize: _scaled(size),
  fontWeight: weight,
  fontVariations: [FontVariation('wght', weight.value.toDouble())],
  color: color,
  height: height,
);
