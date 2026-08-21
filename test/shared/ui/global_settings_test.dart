import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(DsGlobalSettings.reset);

  test('changes and resets application-wide settings', () {
    expect(DsGlobalSettings.value, const DsAppSettings());

    DsGlobalSettings.setFontFamily('Georgia');
    DsGlobalSettings.setUiTextSize(16);
    DsGlobalSettings.setEditorTextSize(18);
    DsGlobalSettings.setGradientBackgroundEnabled(true);

    expect(DsGlobalSettings.value.fontFamily, 'Georgia');
    expect(DsGlobalSettings.value.uiTextSize, 16);
    expect(DsGlobalSettings.value.editorTextSize, 18);
    expect(DsGlobalSettings.value.gradientBackgroundEnabled, isTrue);
    expect(uiTextStyle(weight: 600).fontFamily, 'Georgia');
    expect(uiTextStyle(weight: 600).fontVariations, isNull);
    expect(uiHeaderTextStyle().fontFamily, kUiHeaderFontFamily);

    DsGlobalSettings.toggleGradientBackground();
    expect(DsGlobalSettings.value.gradientBackgroundEnabled, isFalse);

    DsGlobalSettings.reset();
    expect(DsGlobalSettings.value, const DsAppSettings());
    expect(DsGlobalSettings.value.fontFamily, 'IBM Plex Sans');
    expect(uiTextStyle(weight: 600).fontVariations, isNull);

    DsGlobalSettings.setFontFamily('Archivo');
    expect(uiTextStyle(weight: 600).fontVariations, isNotEmpty);
  });

  test('UI and editor sizes scale their own typography independently', () {
    expect(uiTextStyle().fontSize, kDefaultUiTextSize);
    expect(uiHeaderTextStyle().fontSize, 14);
    expect(editorTextStyle().fontSize, kDefaultEditorTextSize);

    DsGlobalSettings.setUiTextSize(16);
    expect(uiTextStyle().fontSize, 16);
    expect(uiTextStyle(size: 26).fontSize, 32);
    expect(uiHeaderTextStyle().fontSize, closeTo(14 * 16 / 13, 0.001));
    expect(editorTextStyle().fontSize, kDefaultEditorTextSize);

    DsGlobalSettings.setEditorTextSize(18);
    expect(editorTextStyle().fontSize, 18);
    expect(editorTextStyle(size: 30).fontSize, 36);
    expect(uiTextStyle().fontSize, 16);
  });

  test('rejects invalid global settings', () {
    expect(() => DsGlobalSettings.setFontFamily('  '), throwsArgumentError);
    for (final size in [0.0, -1.0, double.nan, double.infinity]) {
      expect(() => DsGlobalSettings.setUiTextSize(size), throwsArgumentError);
      expect(
        () => DsGlobalSettings.setEditorTextSize(size),
        throwsArgumentError,
      );
    }
  });

  testWidgets('rebuilds UI and editor text from the shared settings', (
    tester,
  ) async {
    await tester.pumpWidget(
      ValueListenableBuilder<DsAppSettings>(
        valueListenable: DsGlobalSettings.listenable,
        builder: (context, settings, _) => MaterialApp(
          theme: dsTheme(Brightness.light, settings: settings),
          home: Scaffold(
            body: Column(
              children: [
                Text('UI', style: uiTextStyle()),
                Text('Header', style: uiHeaderTextStyle()),
                Text('Editor', style: editorTextStyle()),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('UI')).style?.fontSize, 13);
    expect(
      tester.widget<Text>(find.text('Header')).style?.fontFamily,
      kUiHeaderFontFamily,
    );
    expect(tester.widget<Text>(find.text('Editor')).style?.fontSize, 15);

    DsGlobalSettings.setUiTextSize(16);
    DsGlobalSettings.setEditorTextSize(18);
    DsGlobalSettings.setFontFamily('Georgia');
    await tester.pumpAndSettle();

    final ui = tester.widget<Text>(find.text('UI')).style;
    final header = tester.widget<Text>(find.text('Header')).style;
    final editor = tester.widget<Text>(find.text('Editor')).style;
    expect(ui?.fontSize, 16);
    expect(editor?.fontSize, 18);
    expect(ui?.fontFamily, 'Georgia');
    expect(header?.fontFamily, kUiHeaderFontFamily);
    expect(header?.fontSize, closeTo(14 * 16 / 13, 0.001));
    expect(editor?.fontFamily, 'Georgia');
    expect(
      Theme.of(tester.element(find.text('UI')))
          .textTheme
          .bodyMedium
          ?.fontFamily,
      'Georgia',
    );
  });
}
