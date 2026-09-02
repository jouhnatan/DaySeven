/// Renders the shell to an image so the layout can be inspected.
///
/// Run with `--update-goldens` to refresh the checked shell images. They lock
/// down the top bar, the Knowledge Base headers and islands, tree guides, and
/// the bottom bar.
///
/// There is one set of these. The interface has a single palette, so there is
/// no second appearance to photograph.
library;

import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/domain/timeline.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/kb_harness.dart';
import '../../support/test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUpAll(loadTestFonts);

  setUp(() async {
    final dirs = await createTempDirs('dayseven_look');
    temp = dirs.temp;
  });

  Future<ProviderContainer> seededKb(WidgetTester tester) =>
      seededKbContainer(tester, temp);

  Future<ProviderContainer> renderShell(
    WidgetTester tester, {
    bool knowledgeBaseVisible = true,
    Size size = const Size(1280, 820),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await seededKb(tester);
    if (!knowledgeBaseVisible) {
      await tester.runAsync(() async {
        final store = await container.read(appStoreProvider.future);
        await store.setPaneVisibility('knowledgeBase', false);
        container.read(paneVisibilityProvider);
        for (var attempt = 0; attempt < 50; attempt++) {
          if (!container.read(paneVisibilityProvider).knowledgeBase) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        throw StateError('Knowledge Base visibility was not restored');
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dsTheme(),
          home: const DsShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('editor with the tree open', (tester) async {
    await renderShell(tester);
    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor.png'),
    );
  });

  testWidgets('editor with the Knowledge Base hidden', (tester) async {
    await renderShell(tester, knowledgeBaseVisible: false);
    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor_kb_hidden.png'),
    );
  });

  testWidgets('compact title bar', (tester) async {
    await renderShell(tester, size: const Size(640, 700));
    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor_compact.png'),
    );
  });

  testWidgets('active editor toolbar island', (tester) async {
    final container = await renderShell(tester);
    await tester.runAsync(
      () => container
          .read(documentControllerProvider.notifier)
          .open('Timeline.md'),
    );
    container.read(viewProvider.notifier).state = DsView.editor;
    await tester.pumpAndSettle();

    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.controller is RichTextController,
      description: 'document paragraph TextField',
    );
    await tester.tap(paragraph.first);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor_toolbar.png'),
    );

    await tester.pump(const Duration(milliseconds: 650));
    await tester.runAsync(
      () => container.read(documentControllerProvider.notifier).flush(),
    );
  });

  testWidgets('the Timelines view', (tester) async {
    final container = await renderShell(tester);
    final kb = container.read(kbSessionProvider)!.kb;

    final path = await tester.runAsync(() async {
      final created = await kb.createObject(
        name: 'Third Age',
        seed: const Timeline(
          id: 'tl-1',
          title: 'Third Age',
          nations: [
            TimelineNation(
              id: 'vale',
              name: 'The Vale',
              color: TimelineColor.teal,
            ),
            TimelineNation(
              id: 'north',
              name: 'The North',
              color: TimelineColor.amber,
            ),
          ],
          items: [
            TimelinePeriodItem(
              id: 'rise',
              title: 'Rise of the North',
              year: 1800,
              endYear: 1850,
              color: TimelineColor.amber,
              nationIds: ['north'],
            ),
            // Off the period's midpoint on purpose: an event centred on a
            // period's centre draws its pill over the period's own.
            TimelineEventItem(
              id: 'fall',
              title: 'The bridge falls',
              year: 1842,
              month: 3,
              mainDocumentPath: 'Places/Aldenmoor.md',
              nationIds: ['vale', 'north'],
            ),
          ],
        ).toJson(),
      );
      await container.read(kbControllerProvider.notifier).refreshTree();
      await container.read(openTimelineProvider.notifier).open(created);
      return created;
    });

    expect(path, 'Third Age.unearth');
    container.read(selectedTimelineItemIdProvider.notifier).state = 'fall';
    await tester.runAsync(
      () => container.read(timelineReaderDocumentProvider.future),
    );
    container.read(viewProvider.notifier).state = DsView.timelines;
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/timelines.png'),
    );
  });
}
