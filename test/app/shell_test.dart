import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/gradient_background/ui/gradient_background.dart';
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
  child: MaterialApp(theme: dsTheme(Brightness.dark), home: const DsShell()),
);

void main() {
  tearDown(DsGlobalSettings.reset);

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
        of: find.byKey(const Key('home-gradient')),
        matching: find.byType(DsIsland),
      ),
      findsNothing,
      reason: 'Home is a full workspace surface, not an editor island',
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

  testWidgets('Home changes the shell background without changing Editor', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      kGradientShellBackgroundDark,
    );

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      DsColors.dark.appBackground,
    );
  });

  testWidgets('the hamburger adds the gradient to other workspace views', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byKey(const Key('gradient-background-base')), findsOneWidget);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(find.text('Gradient on Other Views'), findsOneWidget);
    expect(
      find.byKey(const Key('hamburger-menu-toggle-check-1')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('hamburger-menu-toggle-1')));
    await tester.pumpAndSettle();

    expect(DsGlobalSettings.value.gradientBackgroundEnabled, isTrue);
    expect(find.byKey(const Key('gradient-background-base')), findsOneWidget);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      kGradientShellBackgroundDark,
    );
    expect(find.byKey(const Key('gradient-background-base')), findsOneWidget);
    expect(
      tester
          .widget<DsIsland>(
            find.byWidgetPredicate(
              (widget) => widget is DsIsland && widget.editorSurface,
            ),
          )
          .editorSurface,
      isTrue,
      reason: 'the gradient belongs behind the editor pane, not inside it',
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('hamburger-menu-toggle-check-1')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('hamburger-menu-toggle-1')));
    await tester.pumpAndSettle();

    expect(DsGlobalSettings.value.gradientBackgroundEnabled, isFalse);
    expect(find.byKey(const Key('gradient-background-base')), findsNothing);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      DsColors.dark.appBackground,
    );

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const Key('gradient-background-base')),
      findsOneWidget,
      reason: 'Home keeps its default gradient independently of the toggle',
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

    expect(find.text('App settings'), findsOneWidget);
    expect(find.text('Run updates'), findsNothing);

    // The two toggles are addressed by index elsewhere in this file, so the
    // new entry has to have been appended rather than inserted.
    expect(find.byKey(const Key('hamburger-menu-toggle-0')), findsOneWidget);
    expect(find.byKey(const Key('hamburger-menu-toggle-1')), findsOneWidget);
  });

  testWidgets('the hamburger slides the Knowledge Base out and back in', (
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
      find.byKey(const Key('home-gradient')),
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final slideMid = tester.getSize(
      find.byKey(const Key('knowledge-base-slide-region')),
    );
    final panelMid = tester.getRect(
      find.byKey(const Key('knowledge-base-pane')),
    );
    final workspaceMid = tester.getRect(find.byKey(const Key('home-gradient')));
    expect(slideMid.width, greaterThan(0));
    expect(slideMid.width, lessThan(panelBefore.width + DsSpace.islandGap));
    expect(panelMid.left, greaterThan(panelBefore.left));
    expect(workspaceMid.right, greaterThan(workspaceBefore.right));

    await tester.pumpAndSettle();

    final workspaceHidden = tester.getRect(
      find.byKey(const Key('home-gradient')),
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
      tester.getRect(find.byKey(const Key('home-gradient'))),
      workspaceBefore,
    );

    final visibility = container.read(paneVisibilityProvider.notifier);
    visibility.setKnowledgeBaseVisible(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 75));
    expect(
      tester.getRect(find.byKey(const Key('knowledge-base-pane'))).left,
      greaterThan(panelBefore.left),
    );

    visibility.setKnowledgeBaseVisible(true);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(find.byKey(const Key('knowledge-base-pane'))),
      panelBefore,
      reason: 'reversing mid-animation returns smoothly to the stored width',
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

    testWidgets('the gap between the islands is the island gap', (
      tester,
    ) async {
      await pumpWide(tester);

      final rail = tester.getRect(find.byType(DsIsland).at(0));
      final editor = tester.getRect(find.byKey(const Key('home-gradient')));

      expect(editor.left - rail.right, DsSpace.islandGap);
    });

    testWidgets('workspace and side menus keep the same bounds across views', (
      tester,
    ) async {
      await pumpWide(tester);

      final views = tester.getRect(
        find
            .descendant(
              of: find.byType(ViewsMenu),
              matching: find.byType(DsIsland),
            )
            .first,
      );
      final homeViewsMenu = tester.getRect(find.byType(ViewsMenu));
      final homeKnowledgeBaseMenu = tester.getRect(
        find.byType(KnowledgeBaseMenu),
      );
      final workspace = tester.getRect(find.byKey(const Key('home-gradient')));
      final notifications = tester.getRect(find.byType(NotificationsPanel));

      expect(workspace.top, views.top);
      expect(workspace.bottom, notifications.bottom);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(of: find.byType(EditorScreen), matching: find.byType(DsIsland))
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

    testWidgets('the bottom bar sits one island gap below the islands', (
      tester,
    ) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(of: find.byType(EditorScreen), matching: find.byType(DsIsland))
            .first,
      );
      final bar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );

      expect(
        bar.top - editor.bottom,
        DsSpace.islandGap,
        reason: 'the same distance that separates the islands',
      );
    });

    testWidgets('Home reserves the Editor bar spacing below its menus', (
      tester,
    ) async {
      await pumpWide(tester);

      final views = tester.getRect(
        find
            .descendant(
              of: find.byType(ViewsMenu),
              matching: find.byType(DsIsland),
            )
            .first,
      );
      final notifications = tester.getRect(find.byType(NotificationsPanel));
      final hiddenButton = tester.getRect(
        find.byKey(const Key('bottom-bar-footprint')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(views.left - window.left, DsSpace.pane);
      expect(notifications.left - window.left, DsSpace.pane);
      expect(notifications.bottom, greaterThan(views.bottom));
      expect(hiddenButton.top - notifications.bottom, DsSpace.islandGap);
      expect(window.bottom - hiddenButton.bottom, DsSpace.pane);
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
              matching: find.byType(DsIsland),
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
        editor.bottom - 1,
        reason: 'the shelf sits just inside the editor island hairline',
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
              matching: find.byType(DsIsland),
            )
            .first,
      );

      // Widen the Knowledge Base panel by dragging the gap beside it.
      await tester.dragFrom(
        Offset(
          editorBefore.right + DsSpace.islandGap / 2,
          editorBefore.center.dy,
        ),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();

      final editor = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const Key('editor-search-card')),
              matching: find.byType(DsIsland),
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

    testWidgets('the bar keeps the window margin beneath it', (tester) async {
      await pumpWide(tester);

      await tester.tap(find.text('Editor'));
      await tester.pumpAndSettle();

      final bar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(window.bottom - bar.bottom, DsSpace.pane);
    });
  });

  testWidgets('the editor and side panels share the lighter surface', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(DsColors.dark.island, DsColors.dark.editorSurface);
    expect(DsColors.light.island, DsColors.light.editorSurface);
    expect(DsColors.dark.appBackground, isNot(DsColors.dark.editorSurface));
    expect(DsColors.light.appBackground, isNot(DsColors.light.editorSurface));
  });

  test('the shared Card surface is darker than its island', () {
    expect(
      DsColors.light.cardSurface.computeLuminance(),
      lessThan(DsColors.light.island.computeLuminance()),
    );
    expect(
      DsColors.dark.cardSurface.computeLuminance(),
      lessThan(DsColors.dark.island.computeLuminance()),
    );
  });

  test('island and button outlines are darker than their surfaces', () {
    expect(
      DsColors.dark.surfaceOutline.computeLuminance(),
      lessThan(DsColors.dark.island.computeLuminance()),
    );
    expect(
      DsColors.light.surfaceOutline.computeLuminance(),
      lessThan(DsColors.light.island.computeLuminance()),
    );
  });

  test('light outlines are darker than the grey window background', () {
    final background = DsColors.light.appBackground.computeLuminance();

    expect(
      DsColors.light.surfaceOutline.computeLuminance(),
      lessThan(background),
    );
    expect(DsColors.light.border.computeLuminance(), lessThan(background));
    expect(
      DsColors.light.surfaceOutline.computeLuminance(),
      lessThan(DsColors.light.border.computeLuminance()),
      reason: 'island edges should read more clearly than internal lines',
    );
  });
}
