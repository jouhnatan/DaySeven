import 'package:dayseven/features/editing_toolbar/ui/special_character_picker.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_fonts.dart';

void main() {
  setUpAll(loadTestFonts);

  Future<void> openPicker(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: dsTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSpecialCharacterPicker(context),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Finder searchField() => find.descendant(
    of: find.byKey(const Key('special-character-search')),
    matching: find.byType(TextField),
  );

  testWidgets('is a square modal with framed character-and-name tiles', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openPicker(tester);

    expect(
      tester.getSize(find.byKey(const Key('special-character-picker'))),
      const Size(480, 480),
    );
    expect(find.text('Special characters'), findsOneWidget);
    expect(find.text('Search characters'), findsOneWidget);
    expect(find.byKey(const Key('special-character-grid')), findsOneWidget);

    final emDash = find.byKey(const ValueKey('special-character-—'));
    final button = tester.widget<DsButton>(emDash);
    expect(button.framed, isTrue);
    expect(
      find.descendant(of: emDash, matching: find.text('—')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: emDash, matching: find.text('Em dash')),
      findsOneWidget,
    );
  });

  testWidgets('filters by case-insensitive name and exact character', (
    tester,
  ) async {
    await openPicker(tester);

    await tester.enterText(searchField(), 'EuRo SiGn');
    await tester.pump();
    expect(find.byKey(const ValueKey('special-character-€')), findsOneWidget);
    expect(find.byKey(const ValueKey('special-character-—')), findsNothing);

    await tester.enterText(searchField(), 'Ω');
    await tester.pump();
    expect(find.byKey(const ValueKey('special-character-Ω')), findsOneWidget);
    expect(find.text('Greek capital letter omega'), findsOneWidget);
  });

  testWidgets('shows an empty state and Close dismisses without a choice', (
    tester,
  ) async {
    await openPicker(tester);

    await tester.enterText(searchField(), 'definitely not a character');
    await tester.pump();
    expect(find.text('No characters found'), findsOneWidget);

    await tester.tap(find.text('Close').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('special-character-picker')), findsNothing);
  });

  testWidgets('a tile returns its character and closes the picker', (
    tester,
  ) async {
    String? chosen;
    await tester.pumpWidget(
      MaterialApp(
        theme: dsTheme(),
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                chosen = await showSpecialCharacterPicker(context);
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(searchField(), 'check mark');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('special-character-✓')));
    await tester.pumpAndSettle();

    expect(chosen, '✓');
    expect(find.byKey(const Key('special-character-picker')), findsNothing);
  });

  testWidgets('keyboard traversal can choose a grid tile', (tester) async {
    await openPicker(tester);
    await tester.enterText(searchField(), 'em dash');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('special-character-picker')), findsNothing);
  });

  testWidgets('matches the special-character picker golden', (tester) async {
    tester.view.physicalSize = const Size(800, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await openPicker(tester);

    await expectLater(
      find.byKey(const Key('special-character-dialog')),
      matchesGoldenFile('goldens/special_character_picker.png'),
    );
  });
}
