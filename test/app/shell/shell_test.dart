import 'dart:io';

import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_menu.dart';
import 'package:dayseven/features/notifications/ui/notifications_panel.dart';
import 'package:dayseven/features/search/ui/search_bar.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:dayseven/core/macos_lights/traffic_lights_offset.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget harness({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(theme: dsTheme(), home: const DsShell()),
);

Future<void> pumpWideHarness(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1200, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(harness());
}

/// Opens the Views menu, which is where everything placeable is listed.
Future<void> openViews(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('views-menu-button')));
  await tester.pumpAndSettle();
}

Future<void> place(WidgetTester tester, String item) async {
  await openViews(tester);
  await tester.tap(find.byKey(Key('views-menu-$item')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens to the Editor, which invites a Knowledge Base', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.byType(EditorScreen), findsOneWidget);
    expect(
      find.text('Open a document from the Knowledge Base.'),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('centre-workspace')),
        matching: find.byType(EditorScreen),
        matchRoot: true,
      ),
      findsWidgets,
      reason: 'the Editor holds the centre slot',
    );
    expect(
      tester.widget<DsPane>(find.byKey(const Key('centre-workspace'))),
      isA<DsPane>(),
      reason: 'the workspace is a seated pane like every other region',
    );
  });

  testWidgets('the top bar carries the menus, Search and the account', (
    tester,
  ) async {
    await pumpWideHarness(tester);
    await tester.pump();

    expect(find.byKey(const Key('views-menu-button')), findsOneWidget);
    expect(find.byKey(const Key('notifications-bell-button')), findsOneWidget);
    expect(find.byKey(const Key('hamburger-menu-button')), findsOneWidget);
    expect(find.byType(DsSearchBar), findsOneWidget);
  });

  testWidgets('the Views menu lists every workspace and the pane', (
    tester,
  ) async {
    await pumpWideHarness(tester);
    await tester.pump();
    await openViews(tester);

    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Differences'), findsOneWidget);
    expect(find.text('Timelines'), findsOneWidget);
    expect(
      find.text('Knowledge Base'),
      findsNWidgets(2),
      reason: 'the menu names the pane the pane also heads',
    );
  });

  testWidgets('Notifications opens from the bell, not from a rail', (
    tester,
  ) async {
    await pumpWideHarness(tester);
    await tester.pump();

    expect(find.byType(NotificationsPanel), findsNothing);

    await tester.tap(find.byKey(const Key('notifications-bell-button')));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPanel), findsOneWidget);
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
    await pumpWideHarness(tester);
    await tester.pump();

    expect(find.byTooltip('Editor menu'), findsOneWidget);

    await tester.tap(find.byTooltip('Editor menu'));
    await tester.pumpAndSettle();

    expect(find.text('Publish directly'), findsNothing);
    expect(find.text('Sync latest'), findsNothing);
    expect(find.byKey(const Key('editor-menu-differences')), findsOneWidget);

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();

    await place(tester, 'differences');

    expect(
      find.byTooltip('Editor menu'),
      findsNothing,
      reason: 'the Editor gave up the centre slot',
    );
  });

  testWidgets('placing Differences displaces the Editor, and back', (
    tester,
  ) async {
    await pumpWideHarness(tester);
    await tester.pump();

    await place(tester, 'differences');
    expect(find.byType(EditorScreen), findsNothing);

    await place(tester, 'editor');
    expect(find.byType(EditorScreen), findsOneWidget);
  });

  testWidgets('placing Timelines swaps both the workspace and the pane', (
    tester,
  ) async {
    await pumpWideHarness(tester);
    await tester.pump();

    expect(find.byKey(const Key('knowledge-base-pane')), findsOneWidget);

    await place(tester, 'timelines');

    expect(find.byType(EditorScreen), findsNothing);
    expect(find.byKey(const Key('timeline-map-canvas')), findsOneWidget);
    expect(
      find.byKey(const Key('timeline-reader-pane')),
      findsOneWidget,
      reason: 'the reader takes the slot the Knowledge Base tree had',
    );
    expect(find.byKey(const Key('knowledge-base-pane')), findsNothing);

    await place(tester, 'editor');

    expect(find.byType(EditorScreen), findsOneWidget);
    expect(find.byKey(const Key('knowledge-base-pane')), findsOneWidget);
    expect(find.byKey(const Key('timeline-reader-pane')), findsNothing);
  });

  testWidgets('the timeline runs the full width of the window', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pump();
    await place(tester, 'timelines');

    final strip = tester.getRect(find.byKey(const Key('timeline-strip')));
    final shell = tester.getRect(find.byType(DsShell));

    // Unlike the editing toolbar, the strip does not stop where the pane above
    // it begins.
    expect(strip.left, shell.left);
    expect(strip.right, shell.right);
  });

  testWidgets('the Knowledge Base pane sits right of the workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(harness());
    await tester.pump();

    final pane = tester.getRect(find.byKey(const Key('knowledge-base-pane')));
    final workspace = tester.getRect(find.byKey(const Key('centre-workspace')));

    expect(pane.left, greaterThanOrEqualTo(workspace.right));
  });

  testWidgets('Search is in the top bar in every view', (tester) async {
    await pumpWideHarness(tester);
    await tester.pump();

    expect(find.byType(DsSearchBar), findsOneWidget);
    final onEditor = tester.getRect(find.byType(DsSearchBar));

    await place(tester, 'differences');

    expect(
      find.byType(DsSearchBar),
      findsOneWidget,
      reason: 'Search belongs to the shell now, not to one workspace',
    );
    expect(tester.getRect(find.byType(DsSearchBar)), onEditor);
    expect(
      find.byKey(const Key('editor-search-card')),
      findsNothing,
      reason: 'the Editor no longer carries a search shelf',
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
    expect(
      find.byKey(const Key('hamburger-menu-toggle-0')),
      findsNothing,
      reason: 'the Knowledge Base toggle lives in Views now',
    );
  });

  testWidgets(
    'App settings opened from shell does not have Developer tab or metadata toggle',
    (tester) async {
      await tester.pumpWidget(harness());
      await tester.pump();

      await tester.tap(find.byKey(const Key('hamburger-menu-button')));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('Developer'), findsNothing);
      expect(find.text('Show workspace metadata'), findsNothing);
      expect(
        find.byKey(const Key('app-settings-metadata-toggle')),
        findsNothing,
      );
    },
  );

  testWidgets('Views toggles the Knowledge Base out and back in instantly', (
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
      find.byKey(const Key('centre-workspace')),
    );
    final panelBefore = tester.getRect(
      find.byKey(const Key('knowledge-base-pane')),
    );
    final buttonBefore = tester.getRect(
      find.byKey(const Key('views-menu-button')),
    );

    await openViews(tester);
    expect(
      find.byKey(const Key('views-menu-knowledge-base-check')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('views-menu-knowledge-base')));
    await tester.pumpAndSettle();

    final workspaceHidden = tester.getRect(
      find.byKey(const Key('centre-workspace')),
    );
    final slideHidden = tester.getSize(
      find.byKey(const Key('side-pane-slide-region-right')),
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
    expect(
      tester.getRect(find.byKey(const Key('views-menu-button'))),
      buttonBefore,
    );
    expect(hiddenInput.ignoring, isTrue);

    await openViews(tester);
    expect(
      find.byKey(const Key('views-menu-knowledge-base-check')),
      findsNothing,
    );
    await tester.tap(find.byKey(const Key('views-menu-knowledge-base')));
    await tester.pumpAndSettle();

    expect(container.read(paneVisibilityProvider).knowledgeBase, isTrue);
    expect(
      tester.getRect(find.byKey(const Key('knowledge-base-pane'))),
      panelBefore,
    );
    expect(
      tester.getRect(find.byKey(const Key('centre-workspace'))),
      workspaceBefore,
    );

    final visibility = container.read(paneVisibilityProvider.notifier);
    visibility.setKnowledgeBaseVisible(false);
    await tester.pump();
    expect(
      tester
          .getSize(find.byKey(const Key('side-pane-slide-region-right')))
          .width,
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

  group('spacing', () {
    /// Sets a window wide enough that no pane is clamped.
    Future<void> pumpWide(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();
    }

    testWidgets('the workspace runs to the left window edge', (tester) async {
      await pumpWide(tester);

      final workspace = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(
        workspace.left,
        window.left,
        reason: 'nothing stands between the workspace and the edge any more',
      );
    });

    testWidgets('one seam separates the workspace from the Knowledge Base', (
      tester,
    ) async {
      await pumpWide(tester);

      final workspace = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );
      final pane = tester.getRect(find.byKey(const Key('knowledge-base-pane')));

      expect(pane.left - workspace.right, DsSpace.seam);
    });

    testWidgets('the top bar is seated above the panes', (tester) async {
      await pumpWide(tester);

      final bar = tester.getRect(find.byKey(const Key('views-menu-button')));
      final workspace = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(window.top, lessThanOrEqualTo(bar.top));
      expect(bar.bottom, lessThan(workspace.top));
      expect(workspace.top, kDsTopBarHeight + DsSpace.seam);
    });

    testWidgets('Search is centred on the window, not on the workspace', (
      tester,
    ) async {
      await pumpWide(tester);

      final search = tester.getRect(find.byType(DsSearchBar));
      final window = tester.getRect(find.byType(DsShell));
      final workspace = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );

      expect(search.center.dx, closeTo(window.center.dx, 0.5));
      expect(
        search.center.dx,
        isNot(closeTo(workspace.center.dx, 0.5)),
        reason: 'the Knowledge Base pane pushes the workspace centre left',
      );
      expect(search.width, kSearchWidth);
      expect(search.height, kSearchHeight);
      expect(search.center.dy, closeTo(kDsTopBarHeight / 2, 0.5));
      expect(search.top, 6);
      expect(kDsTopBarHeight - search.bottom, 6);
    });

    testWidgets('title-bar actions align with the macOS traffic lights', (
      tester,
    ) async {
      await pumpWide(tester);

      const trafficLightHeight = 14.0;
      const trafficLightCentre =
          TrafficLightsOffset.defaultY + trafficLightHeight / 2;
      final controls = [
        find.byKey(const Key('title-bar-leading-controls')),
        find.byKey(const Key('views-menu-button')),
        find.byKey(const Key('notifications-bell-button')),
        find.byKey(const Key('title-bar-trailing-controls')),
        find.byKey(const Key('hamburger-menu-button')),
      ];

      for (final control in controls) {
        expect(
          tester.getRect(control).center.dy,
          closeTo(trafficLightCentre, 0.5),
        );
      }
      expect(trafficLightCentre, kDsTopBarHeight / 2);
    });

    /// The panel a top-bar menu opens, found through one of its entries.
    Finder menuPanelFor(Finder entry) =>
        find.ancestor(of: entry, matching: find.byType(Material)).first;

    testWidgets('top-bar menus hang from the bottom edge of the bar', (
      tester,
    ) async {
      await pumpWide(tester);

      await openViews(tester);
      expect(
        tester
            .getRect(menuPanelFor(find.byKey(const Key('views-menu-editor'))))
            .top,
        kDsTopBarHeight,
        reason: 'a menu drops from the bar, not from the control inside it',
      );
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('hamburger-menu-button')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(menuPanelFor(find.text('Settings'))).top,
        kDsTopBarHeight,
      );
      await tester.tapAt(const Offset(700, 500));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('notifications-bell-button')));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.byKey(const Key('notifications-popover'))).top,
        kDsTopBarHeight,
      );
    });

    testWidgets('a top-bar menu carries the bar surface down with it', (
      tester,
    ) async {
      await pumpWide(tester);
      await openViews(tester);

      final panel = tester.widget<Material>(
        menuPanelFor(find.byKey(const Key('views-menu-editor'))),
      );
      expect(panel.color, DsColors.cream.bar);
    });

    testWidgets('compact windows hide menu items without clipping Search', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(harness());
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('views-menu-button')), findsNothing);
      expect(find.byKey(const Key('notifications-bell-button')), findsNothing);
      expect(find.byKey(const Key('hamburger-menu-button')), findsOneWidget);

      final search = tester.getRect(find.byType(DsSearchBar));
      final window = tester.getRect(find.byType(DsShell));
      final menu = tester.getRect(
        find.byKey(const Key('hamburger-menu-button')),
      );

      expect(search.center.dx, closeTo(window.center.dx, 0.5));
      expect(search.right, lessThan(menu.left));
      if (Platform.isMacOS) {
        const trafficLightsRight = 20 + 3 * 14 + 2 * 6;
        expect(search.left, greaterThan(trafficLightsRight));
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('Search holds still as the Knowledge Base is resized', (
      tester,
    ) async {
      await pumpWide(tester);

      final before = tester.getRect(find.byType(DsSearchBar));
      final workspaceBefore = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );

      // Widen the Knowledge Base panel by dragging the seam beside it.
      await tester.dragFrom(
        Offset(
          workspaceBefore.right + DsSpace.seam / 2,
          workspaceBefore.center.dy,
        ),
        const Offset(-80, 0),
      );
      await tester.pumpAndSettle();

      expect(
        tester.getRect(find.byKey(const Key('centre-workspace'))).right,
        lessThan(workspaceBefore.right),
        reason: 'the drag did move the seam',
      );
      expect(
        tester.getRect(find.byType(DsSearchBar)),
        before,
        reason: 'Search is the window\'s, so a pane resize does not move it',
      );
    });

    testWidgets('the menus clear the macOS window buttons', (tester) async {
      await pumpWide(tester);

      final inset = find.byKey(const Key('window-buttons-inset'));
      if (!Platform.isMacOS) {
        expect(
          inset,
          findsNothing,
          reason: 'only macOS floats its buttons over the bar',
        );
        return;
      }

      expect(inset, findsOneWidget);
      final views = tester.getRect(find.byKey(const Key('views-menu-button')));
      expect(
        views.left,
        greaterThan(20 + 3 * 14 + 2 * 6),
        reason: 'the buttons sit at x=20 and are 14pt wide, spaced 6pt',
      );
    });

    testWidgets('the bottom bar is seated below the panes', (tester) async {
      await pumpWide(tester);

      final workspace = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );
      final bar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );

      expect(
        bar.top - workspace.bottom,
        DsSpace.seam,
        reason: 'the footer is seated against the panes above it',
      );
    });

    testWidgets('a view without a toolbar reserves the same bar height', (
      tester,
    ) async {
      await pumpWide(tester);

      final editorBar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );

      await place(tester, 'differences');

      final footprint = tester.getRect(
        find.byKey(const Key('bottom-bar-footprint')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(footprint.height, editorBar.height);
      expect(window.bottom, footprint.bottom);
    });

    testWidgets('the bar runs to the bottom of the window', (tester) async {
      await pumpWide(tester);

      final bar = tester.getRect(
        find.byKey(const Key('editor-toolbar-menu-footprint')),
      );
      final window = tester.getRect(find.byType(DsShell));

      expect(window.bottom, bar.bottom);
    });

    testWidgets('the Knowledge Base pane spans the panes\' full height', (
      tester,
    ) async {
      await pumpWide(tester);

      final workspace = tester.getRect(
        find.byKey(const Key('centre-workspace')),
      );
      final menu = tester.getRect(find.byType(KnowledgeBaseMenu));

      expect(menu.top, workspace.top);
      expect(menu.bottom, workspace.bottom);
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
