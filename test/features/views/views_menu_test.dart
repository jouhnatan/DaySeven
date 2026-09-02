import 'package:dayseven/app/view.dart';
import 'package:dayseven/features/views/ui/views_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Mounts the button with the panes the shell would hand it, and reports
  /// what it asked to be toggled.
  Future<ProviderContainer> pumpMenu(
    WidgetTester tester, {
    bool knowledgeBaseVisible = true,
    int pendingDifferencesCount = 0,
    VoidCallback? onToggleKnowledgeBase,
    List<ViewsPaneToggle>? panes,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: ViewsMenuButton(
                panes:
                    panes ??
                    [
                      ViewsPaneToggle(
                        id: 'views-menu-knowledge-base',
                        label: 'Knowledge Base',
                        visible: knowledgeBaseVisible,
                        onToggle: onToggleKnowledgeBase ?? () {},
                      ),
                    ],
                pendingDifferencesCount: pendingDifferencesCount,
              ),
            ),
          ),
        ),
      ),
    );
    return container;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('views-menu-button')));
    await tester.pumpAndSettle();
  }

  testWidgets('lists what can be placed, marking what is', (tester) async {
    final container = await pumpMenu(tester);
    await openMenu(tester);

    expect(find.byKey(const Key('views-menu-editor')), findsOneWidget);
    expect(find.byKey(const Key('views-menu-differences')), findsOneWidget);
    expect(find.byKey(const Key('views-menu-timelines')), findsOneWidget);
    expect(find.byKey(const Key('views-menu-world')), findsOneWidget);
    expect(find.byKey(const Key('views-menu-knowledge-base')), findsOneWidget);

    expect(container.read(viewProvider), DsView.editor);
    expect(find.byKey(const Key('views-menu-editor-check')), findsOneWidget);
    expect(
      find.byKey(const Key('views-menu-differences-check')),
      findsNothing,
      reason: 'the workspaces share one slot, so only one is placed',
    );
    expect(find.byKey(const Key('views-menu-timelines-check')), findsNothing);
    expect(
      find.byKey(const Key('views-menu-knowledge-base-check')),
      findsOneWidget,
    );
  });

  testWidgets('placing Differences displaces the Editor, and back', (
    tester,
  ) async {
    final container = await pumpMenu(tester);

    await openMenu(tester);
    await tester.tap(find.byKey(const Key('views-menu-differences')));
    await tester.pumpAndSettle();
    expect(container.read(viewProvider), DsView.differences);

    await openMenu(tester);
    expect(find.byKey(const Key('views-menu-editor-check')), findsNothing);
    expect(
      find.byKey(const Key('views-menu-differences-check')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('views-menu-editor')));
    await tester.pumpAndSettle();
    expect(container.read(viewProvider), DsView.editor);
  });

  testWidgets('placing Timelines displaces whatever held the slot', (
    tester,
  ) async {
    final container = await pumpMenu(tester);

    await openMenu(tester);
    await tester.tap(find.byKey(const Key('views-menu-timelines')));
    await tester.pumpAndSettle();
    expect(container.read(viewProvider), DsView.timelines);

    await openMenu(tester);
    expect(find.byKey(const Key('views-menu-timelines-check')), findsOneWidget);
    expect(find.byKey(const Key('views-menu-editor-check')), findsNothing);
    expect(find.byKey(const Key('views-menu-differences-check')), findsNothing);

    await tester.tap(find.byKey(const Key('views-menu-editor')));
    await tester.pumpAndSettle();
    expect(container.read(viewProvider), DsView.editor);
  });

  testWidgets('placing World displaces whatever held the slot', (tester) async {
    final container = await pumpMenu(tester);

    await openMenu(tester);
    expect(find.byKey(const Key('views-menu-world-check')), findsNothing);
    await tester.tap(find.byKey(const Key('views-menu-world')));
    await tester.pumpAndSettle();
    expect(container.read(viewProvider), DsView.world);

    await openMenu(tester);
    expect(find.byKey(const Key('views-menu-world-check')), findsOneWidget);
  });

  testWidgets('the panes it lists are the ones it was handed', (tester) async {
    var toggled = '';
    await pumpMenu(
      tester,
      panes: [
        ViewsPaneToggle(
          id: 'views-menu-timeline-editor',
          label: 'Events & ages',
          visible: true,
          onToggle: () => toggled = 'editor',
        ),
        ViewsPaneToggle(
          id: 'views-menu-timeline-reader',
          label: 'Reader',
          visible: false,
          onToggle: () => toggled = 'reader',
        ),
      ],
    );
    await openMenu(tester);

    expect(find.byKey(const Key('views-menu-knowledge-base')), findsNothing);
    expect(
      find.byKey(const Key('views-menu-timeline-editor-check')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('views-menu-timeline-reader-check')),
      findsNothing,
      reason: 'a hidden pane carries no mark',
    );

    await tester.tap(find.byKey(const Key('views-menu-timeline-reader')));
    await tester.pumpAndSettle();
    expect(toggled, 'reader');
  });

  testWidgets('choosing the workspace already placed changes nothing', (
    tester,
  ) async {
    final container = await pumpMenu(tester);

    await openMenu(tester);
    await tester.tap(find.byKey(const Key('views-menu-editor')));
    await tester.pumpAndSettle();

    expect(container.read(viewProvider), DsView.editor);
  });

  testWidgets('the Knowledge Base toggles without displacing a workspace', (
    tester,
  ) async {
    var toggled = 0;
    final container = await pumpMenu(
      tester,
      knowledgeBaseVisible: false,
      onToggleKnowledgeBase: () => toggled++,
    );

    await openMenu(tester);
    expect(
      find.byKey(const Key('views-menu-knowledge-base-check')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('views-menu-knowledge-base')));
    await tester.pumpAndSettle();

    expect(toggled, 1);
    expect(container.read(viewProvider), DsView.editor);
  });

  testWidgets('pending proposals badge the row and mark the closed button', (
    tester,
  ) async {
    await pumpMenu(tester, pendingDifferencesCount: 3);

    expect(find.byKey(const Key('views-menu-pending-dot')), findsOneWidget);

    await openMenu(tester);
    expect(find.byKey(const Key('views-differences-badge')), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
  });

  testWidgets('with nothing pending, neither mark is drawn', (tester) async {
    await pumpMenu(tester);

    expect(find.byKey(const Key('views-menu-pending-dot')), findsNothing);

    await openMenu(tester);
    expect(find.byKey(const Key('views-differences-badge')), findsNothing);
  });
}
