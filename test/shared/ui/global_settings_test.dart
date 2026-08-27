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
    // The picker is a document preference. Chrome keeps its own face so that
    // controls, menus and labels read the same whatever a document is set in.
    expect(editorTextStyle(weight: 600).fontFamily, 'Georgia');
    expect(uiTextStyle(weight: 600).fontFamily, kUiFontFamily);
    expect(uiTextStyle(weight: 600).fontVariations, isNull);
    expect(uiHeaderTextStyle().fontFamily, kUiHeaderFontFamily);

    DsGlobalSettings.toggleGradientBackground();
    expect(DsGlobalSettings.value.gradientBackgroundEnabled, isFalse);

    DsGlobalSettings.reset();
    expect(DsGlobalSettings.value, const DsAppSettings());
    expect(DsGlobalSettings.value.fontFamily, kDefaultFontFamily);
    expect(editorTextStyle(weight: 600).fontVariations, isNull);

    // Archivo is variable on the weight axis, so it needs the variation rather
    // than a registered static face. Chrome is unaffected either way.
    DsGlobalSettings.setFontFamily('Archivo');
    expect(editorTextStyle(weight: 600).fontVariations, isNotEmpty);
    expect(uiTextStyle(weight: 600).fontVariations, isNull);
  });

  test('UI and editor sizes scale their own typography independently', () {
    expect(uiTextStyle().fontSize, kDefaultUiTextSize);
    expect(uiHeaderTextStyle().fontSize, 14.5);
    expect(editorTextStyle().fontSize, kDefaultEditorTextSize);

    DsGlobalSettings.setUiTextSize(16);
    expect(uiTextStyle().fontSize, 16);
    expect(uiTextStyle(size: 26).fontSize, 32);
    expect(uiHeaderTextStyle().fontSize, closeTo(14.5 * 16 / 13, 0.001));
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
          theme: dsTheme(settings: settings),
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
    expect(header?.fontFamily, kUiHeaderFontFamily);
    expect(header?.fontSize, closeTo(14.5 * 16 / 13, 0.001));

    // Both sizes still follow their own preference; only the *family* has
    // stopped being shared. Document text takes the picked face, chrome does
    // not, and neither does the Material text theme the chrome is built on.
    expect(editor?.fontFamily, 'Georgia');
    expect(ui?.fontFamily, kUiFontFamily);
    expect(
      Theme.of(tester.element(find.text('UI')))
          .textTheme
          .bodyMedium
          ?.fontFamily,
      kUiFontFamily,
    );
  });
}
