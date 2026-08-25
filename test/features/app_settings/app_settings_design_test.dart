import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/app_settings/ui/app_settings_design.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// The palette this design is specified in, as written in the source design.
///
/// Pinned because these are not values anybody should be free to nudge: the
/// dialog is meant to be that design, not something near it. The grain is the
/// thing most likely to pull them off — it blends into every surface — which
/// is why it uses a mode whose identity leaves the colour underneath alone.
const _specified = <String, (Color, int)>{
  'paper': (AppSettingsPalette.paper, 0xD9D9D9),
  'paperHi': (AppSettingsPalette.paperHi, 0xE4E4E2),
  'paperLo': (AppSettingsPalette.paperLo, 0xCDCDCB),
  'ink': (AppSettingsPalette.ink, 0x1E1E1E),
  'ink60': (AppSettingsPalette.ink60, 0x5A5A58),
  'ink40': (AppSettingsPalette.ink40, 0x87877F),
  'inkTint': (AppSettingsPalette.inkTint, 0xC6C6C4),
  'charcoal': (AppSettingsPalette.charcoal, 0x2B2B29),
  'green': (AppSettingsPalette.green, 0x0E3721),
  'greenHover': (AppSettingsPalette.greenHover, 0x154429),
  'greenActive': (AppSettingsPalette.greenActive, 0x0A2B19),
  'greenTint': (AppSettingsPalette.greenTint, 0xC3CEC5),
  'greenTint2': (AppSettingsPalette.greenTint2, 0xAFBFB2),
  'red': (AppSettingsPalette.red, 0x6B1712),
  'redHover': (AppSettingsPalette.redHover, 0x84201A),
  'redTint': (AppSettingsPalette.redTint, 0xD2C4C1),
  'rule': (AppSettingsPalette.rule, 0xB4B4B2),
};

void main() {
  test('the palette is the one the design specifies', () {
    for (final entry in _specified.entries) {
      final (colour, expected) = entry.value;
      expect(
        colour.toARGB32() & 0xFFFFFF,
        expected,
        reason: '${entry.key} should be #${expected.toRadixString(16)}',
      );
      expect(
        colour.a,
        1.0,
        reason:
            '${entry.key}: the design is flat, and '
            'every fill in it is opaque',
      );
    }
  });

  test('the type scale follows the UI text size', () {
    final atDefault = appSettingsBody().fontSize!;

    DsGlobalSettings.setUiTextSize(kDefaultUiTextSize * 2);
    addTearDown(DsGlobalSettings.reset);

    expect(
      appSettingsBody().fontSize,
      closeTo(atDefault * 2, 0.01),
      reason:
          'the design states fixed sizes, but one dialog that ignores a '
          'preference every other surface honours would be worse than exact',
    );
  });
}
