import 'package:dayseven/app/theme.dart';
import 'package:dayseven/search/search_bar.dart';
import 'package:dayseven/ui/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: dsTheme(Brightness.dark), home: const DsShell()),
);

void main() {
  testWidgets('opens to Home, showing the welcome and Recent files', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Welcome back!'), findsOneWidget);
    expect(find.text('Recent files'), findsOneWidget);
  });

  testWidgets('the service rail lists only Home and Editor', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    // Differences is not a service; it must not appear in the rail.
    expect(find.text('Differences'), findsNothing);
  });

  testWidgets('Differences appears only while the Editor service is showing', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Differences'), findsNothing);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(find.text('Differences'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.text('Differences'), findsNothing);
  });

  testWidgets('the Knowledge Base island shows on the right of the editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pump();

    final island = tester.getTopLeft(find.text('Knowledge Base'));
    final welcome = tester.getTopLeft(find.text('Welcome back!'));
    expect(
      island.dx,
      greaterThan(welcome.dx),
      reason: 'the island belongs on the right-hand side',
    );
  });

  testWidgets('the search bar sits at the top of the application', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final search = tester.getTopLeft(find.text('Search'));
    final rail = tester.getTopLeft(find.text('Home'));
    expect(search.dy, lessThan(rail.dy));
  });

  testWidgets('the welcome message is set in Aleo', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final text = tester.widget<Text>(find.text('Welcome back!'));
    expect(text.style?.fontFamily, kEditorFontFamily);
  });

  testWidgets('with no Knowledge Base open, the editor invites one', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(
      find.text('Open a document from the Knowledge Base.'),
      findsOneWidget,
    );
  });

  group('spacing', () {
    /// Sets a window wide enough that no pane is clamped.
    Future<void> pumpWide(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
    }

    testWidgets('the gap between the islands is the island gap', (
      tester,
    ) async {
      await pumpWide(tester);

      final rail = tester.getRect(find.byType(DsIsland).at(0));
      final editor = tester.getRect(find.byType(DsIsland).at(1));

      expect(editor.left - rail.right, DsSpace.islandGap);
    });

    testWidgets('the bottom bar sits one island gap below the islands', (
      tester,
    ) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final editor = tester.getRect(find.byType(DsIsland).at(1));
      final button = tester.getRect(find.byType(DifferencesButton));

      expect(
        button.top - editor.bottom,
        DsSpace.islandGap,
        reason: 'the same distance that separates the islands',
      );
    });

    testWidgets('the islands keep the window margin on every other edge', (
      tester,
    ) async {
      await pumpWide(tester);

      final rail = tester.getRect(find.byType(DsIsland).at(0));
      final window = tester.getRect(find.byType(DsShell));

      expect(rail.left - window.left, DsSpace.pane);
      // With Home showing there is no bar, so the islands run to the margin.
      expect(window.bottom - rail.bottom, DsSpace.pane);
    });

    testWidgets('the search bar is centred over the workspace', (tester) async {
      await pumpWide(tester);

      final editor = tester.getRect(find.byType(DsIsland).at(1));
      final search = tester.getRect(find.byType(DsSearchBar));

      expect(
        search.center.dx,
        closeTo(editor.center.dx, 0.5),
        reason: 'centred over the editor, not the window',
      );
      expect(search.width, kSearchWidth);
      expect(search.height, kSearchHeight);
      expect(search.bottom, lessThan(editor.top));
    });

    testWidgets('the search bar stays with the editor as panes resize', (
      tester,
    ) async {
      await pumpWide(tester);

      final before = tester.getRect(find.byType(DsSearchBar)).center.dx;
      final editorBefore = tester.getRect(find.byType(DsIsland).at(1));

      // Widen the Knowledge Base panel by dragging the gap beside it.
      await tester.dragFrom(
        Offset(
          editorBefore.right + DsSpace.islandGap / 2,
          editorBefore.center.dy,
        ),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();

      final editor = tester.getRect(find.byType(DsIsland).at(1));
      final search = tester.getRect(find.byType(DsSearchBar));

      expect(search.center.dx, closeTo(editor.center.dx, 0.5));
      expect(
        search.center.dx,
        isNot(closeTo(before, 0.5)),
        reason: 'it moved with the workspace',
      );
    });

    testWidgets('the bar keeps the window margin beneath it', (tester) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final button = tester.getRect(find.byType(DifferencesButton));
      final window = tester.getRect(find.byType(DsShell));

      expect(window.bottom - button.bottom, DsSpace.pane);
    });
  });

  testWidgets('the three surface tones are distinct', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    const c = DsColors.dark;
    expect(c.appBackground, isNot(c.island));
    expect(c.island, isNot(c.editorSurface));
    expect(c.appBackground, isNot(c.editorSurface));
  });
}
