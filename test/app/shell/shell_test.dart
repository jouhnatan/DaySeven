import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_menu.dart';
import 'package:dayseven/features/notifications/ui/notifications_panel.dart';
import 'package:dayseven/features/search/ui/search_bar.dart';
import 'package:dayseven/features/views/ui/views_menu.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: dsTheme(), home: const DsShell()),
);

void main() {
  testWidgets('opens to Home, showing the greeting and both cards', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Ready to build, Guest?'), findsOneWidget);
    expect(find.text('Recent Files'), findsOneWidget);
    expect(find.text('User Settings'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byKey(const Key('home-workspace')),
        matching: find.byType(DsPane),
      ),
      findsOneWidget,
      reason: 'Home is a seated pane like every other region',
    );
  });

  testWidgets('the Views menu lists Home, Editor, and Differences', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Views'), findsOneWidget);
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Differences'), findsOneWidget);
  });

  testWidgets('every workspace uses the standard shell background', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      DsColors.cream.appBackground,
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Gradient on Other Views'), findsNothing);
    await tester.tapAt(Offset.zero);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      DsColors.cream.appBackground,
    );
    expect(
      tester
          .widget<DsPane>(
            find.byWidgetPredicate(
              (widget) => widget is DsPane && widget.editorSurface,
            ),
          )
          .editorSurface,
      isTrue,
    );
  });

  testWidgets('the Editor overflow menu contains Differences', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byTooltip('Editor menu'), findsNothing);
    expect(find.text('Differences'), findsOneWidget);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Editor menu'), findsOneWidget);
    expect(find.text('Differences'), findsOneWidget);

    await tester.tap(find.byTooltip('Editor menu'));
    await tester.pumpAndSettle();

    expect(find.text('Publish directly'), findsNothing);
    expect(find.text('Sync latest'), findsNothing);
    expect(find.text('Differences'), findsNWidgets(2));
    expect(find.byKey(const Key('editor-menu-differences')), findsOneWidget);

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Editor menu'), findsNothing);
    expect(find.text('Differences'), findsOneWidget);
  });

  testWidgets('the Knowledge Base menu shows on the right of the editor', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pump();

    final island = tester.getTopLeft(find.text('Knowledge Base'));
    final welcome = tester.getTopLeft(find.text('Ready to build, Guest?'));
    expect(
      island.dx,
      greaterThan(welcome.dx),
      reason: 'the island belongs on the right-hand side',
    );
  });

  testWidgets('Search belongs to the Editor overlay, not Home', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byType(DsSearchBar), findsNothing);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(find.byType(DsSearchBar), findsOneWidget);
    expect(
      find.ancestor(
        of: find.byType(DsSearchBar),
        matching: find.byKey(const Key('editor-search-card')),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the hamburger remains available for future tools', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byTooltip('Menu'), findsOneWidget);
  });

  // Updating moved behind App settings, where the version it is updating from
  // is visible. Leaving both would offer the same action twice.
  testWidgets('the hamburger offers App settings, not Run updates', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.byKey(const Key('hamburger-menu-button')));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Run updates'), findsNothing);

    expect(find.byKey(const Key('hamburger-menu-toggle-0')), findsOneWidget);
    expect(find.byKey(const Key('hamburger-menu-toggle-1')), findsNothing);
  });

  testWidgets('the hamburger toggles the Knowledge Base out and back in instantly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(DsShell)),
    );
    final workspaceBefore = tester.getRect(
      find.byKey(const Key('home-workspace')),
    );
    final panelBefore = tester.getRect(
      find.byKey(const Key('knowledge-base-pane')),
    );
    final buttonBefore = tester.getRect(find.byTooltip('Menu'));

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('hamburger-menu-toggle-check-0')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('hamburger-menu-toggle-0')));
    await tester.pumpAndSettle();

    final workspaceHidden = tester.getRect(
      find.byKey(const Key('home-workspace')),
    );
    final slideHidden = tester.getSize(
      find.byKey(const Key('knowledge-base-slide-region')),
    );
    final hiddenInput = tester.widget<IgnorePointer>(
      find
          .ancestor(
            of: find.byKey(const Key('knowledge-base-pane')),
            matching: find.byType(IgnorePointer),
          )
          .first,
    );
    expect(container.read(paneVisibilityProvider).knowledgeBase, isFalse);
    expect(slideHidden.width, 0);
    expect(workspaceHidden.right, greaterThan(workspaceBefore.right));
    expect(tester.getRect(find.byTooltip('Menu')), buttonBefore);
    expect(hiddenInput.ignoring, isTrue);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('hamburger-menu-toggle-check-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('hamburger-menu-toggle-0')));
    await tester.pumpAndSettle();

    expect(container.read(paneVisibilityProvider).knowledgeBase, isTrue);
    expect(
      tester.getRect(find.byKey(const Key('knowledge-base-pane'))),
      panelBefore,
    );
    expect(
      tester.getRect(find.byKey(const Key('home-workspace'))),
      workspaceBefore,
    );

    final visibility = container.read(paneVisibilityProvider.notifier);
    visibility.setKnowledgeBaseVisible(false);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(const Key('knowledge-base-slide-region'))).width,
      0,
      reason: 'closes instantly on state change without animation lag',
    );

    visibility.setKnowledgeBaseVisible(true);
    await tester.pump();
    expect(
      tester.getRect(find.byKey(const Key('knowledge-base-pane'))),
      panelBefore,
      reason: 'opens instantly on state change without animation lag',
    );
  });

  testWidgets('the welcome message is centered in Geist Pixel', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final text = tester.widget<Text>(find.text('Ready to build, Guest?'));
    expect(text.style?.fontFamily, kUiHeaderFontFamily);
    expect(text.textAlign, TextAlign.center);
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

    testWidgets('one seam separates the rail from the workspace', (
      tester,
    ) async {
      await pumpWide(tester);

      final rail = tester.getRect(find.byType(DsPane).at(0));
      final editor = tester.getRect(find.byKey(const Key('home-workspace')));

      expect(editor.left - rail.right, DsSpace.seam);
    });

    testWidgets('workspace and side menus keep the same bounds across views', (
      tester,
    ) async {
      await pumpWide(tester);

      final views = tester.getRect(find.byType(ViewsMenu));
      final homeViewsMenu = tester.getRect(find.byType(ViewsMenu));
      final homeKnowledgeBaseMenu = tester.getRect(
        find.byType(KnowledgeBaseMenu),
      );
      final workspace = tester.getRect(find.byKey(const Key('home-workspace')));
      final notifications = tester.getRect(find.byType(NotificationsPanel));

      expect(workspace.top, views.top);
      expect(workspace.bottom, notifications.bottom);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(
              of: find.byType(EditorScreen),
              matching: find.byType(DsPane),
            )
            .first,
      );
      expect(editor.top, workspace.top, reason: 'the editor spans the pane');
      expect(editor.bottom, workspace.bottom);
      expect(tester.getRect(find.byType(ViewsMenu)), homeViewsMenu);
      expect(
        tester.getRect(find.byType(KnowledgeBaseMenu)),
        homeKnowledgeBaseMenu,
      );
    });

    testWidgets('the bottom bar is seated below the panes', (
      tester,
    ) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(
              of: find.byType(EditorScreen),
              matching: find.byType(DsPane),
            )
            .first,
      );
      final bar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );

      expect(
        bar.top - editor.bottom,
        DsSpace.seam,
        reason: 'the footer is seated against the panes above it',
      );
    });

    testWidgets('Home reserves the Editor bar spacing below its menus', (
      tester,
    ) async {
      await pumpWide(tester);

      final views = tester.getRect(find.byType(ViewsMenu));
      final notifications = tester.getRect(find.byType(NotificationsPanel));
      final hiddenButton = tester.getRect(
        find.byKey(const Key('bottom-bar-footprint')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(views.left, window.left, reason: 'the rail runs to the edge');
      expect(notifications.left, window.left);
      expect(notifications.bottom, greaterThan(views.bottom));
      expect(hiddenButton.top - notifications.bottom, DsSpace.seam);
      expect(window.bottom, hiddenButton.bottom);
    });

    testWidgets('the Search shelf overlays the bottom of Editor', (
      tester,
    ) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('editor-search-card')),
              matching: find.byType(DsPane),
            )
            .first,
      );
      final search = tester.getRect(find.byType(DsSearchBar));
      final card = tester.getRect(find.byKey(const Key('editor-search-card')));
      final cardWidget = tester.widget<DsCard>(
        find.byKey(const Key('editor-search-card')),
      );

      expect(
        search.center.dx,
        closeTo(editor.center.dx, 0.5),
        reason: 'Search is centred inside the editor, not the window',
      );
      expect(search.width, kSearchWidth);
      expect(search.height, kSearchHeight);
      expect(
        card.bottom,
        editor.bottom,
        reason: 'the shelf sits flush with the bottom of the editor pane',
      );
      expect(card.height, kEditorSearchCardHeight);
      expect(search.top, greaterThan(card.top));
      expect(search.bottom, lessThan(card.bottom));
      expect(cardWidget.separator, DsCardSeparator.top);
    });

    testWidgets('the search bar stays with the editor as panes resize', (
      tester,
    ) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final before = tester.getRect(find.byType(DsSearchBar)).center.dx;
      final editorBefore = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('editor-search-card')),
              matching: find.byType(DsPane),
            )
            .first,
      );

      // Widen the Knowledge Base panel by dragging the gap beside it.
      await tester.dragFrom(
        Offset(
          editorBefore.right + DsSpace.seam / 2,
          editorBefore.center.dy,
        ),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('editor-search-card')),
              matching: find.byType(DsPane),
            )
            .first,
      );
      final search = tester.getRect(find.byType(DsSearchBar));

      expect(search.center.dx, closeTo(editor.center.dx, 0.5));
      expect(
        search.center.dx,
        isNot(closeTo(before, 0.5)),
        reason: 'it moved with the workspace',
      );
    });

    testWidgets('the bar runs to the bottom of the window', (tester) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final bar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(window.bottom, bar.bottom);
    });
  });

  testWidgets('the editor and side panels share the lighter surface', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(DsColors.cream.island, DsColors.cream.editorSurface);
    expect(DsColors.cream.island, DsColors.cream.editorSurface);
    expect(DsColors.cream.appBackground, isNot(DsColors.cream.editorSurface));
    expect(DsColors.cream.appBackground, isNot(DsColors.cream.editorSurface));
  });

  test('the shared Card surface is darker than its island', () {
    expect(
      DsColors.cream.cardSurface.computeLuminance(),
      lessThan(DsColors.cream.island.computeLuminance()),
    );
    expect(
      DsColors.cream.cardSurface.computeLuminance(),
      lessThan(DsColors.cream.island.computeLuminance()),
    );
  });

  test('pane and button outlines are darker than their surfaces', () {
    expect(
      DsColors.cream.surfaceOutline.computeLuminance(),
      lessThan(DsColors.cream.island.computeLuminance()),
    );
    expect(
      DsColors.cream.surfaceOutline.computeLuminance(),
      lessThan(DsColors.cream.island.computeLuminance()),
    );
  });

  test('light outlines are darker than the grey window background', () {
    final background = DsColors.cream.appBackground.computeLuminance();

    expect(
      DsColors.cream.surfaceOutline.computeLuminance(),
      lessThan(background),
    );
    expect(DsColors.cream.border.computeLuminance(), lessThan(background));
    expect(
      DsColors.cream.surfaceOutline.computeLuminance(),
      lessThan(DsColors.cream.border.computeLuminance()),
      reason: 'object edges should read more clearly than internal lines',
    );
  });
}
