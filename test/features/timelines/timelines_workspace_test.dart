/// The Timelines view: the reader pane's two jobs, and the two expansions.
library;

import 'dart:io';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/domain/timeline.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/kb_harness.dart';
import '../../support/widget_harness.dart';

void main() {
  late Directory temp;

  setUp(() async {
    final dirs = await createTempDirs('dayseven_timelines_test');
    temp = dirs.temp;
  });

  /// A seeded Knowledge Base with one timeline object on disk whose only event
  /// points at a document that is really there.
  ///
  /// The listing is overridden rather than read: a `FutureProvider` first read
  /// from inside the widget tree starts its disk I/O under fake time, and the
  /// Knowledge Base's folder watcher keeps re-emitting a session while the
  /// test writes into that folder. What is under test here is the pane, not
  /// the directory walk — `readObjects` has its own test in
  /// `test/shared/kb/objects_test.dart`.
  Future<ProviderContainer> timelinesView(WidgetTester tester) async {
    final container = await seededKbContainer(
      tester,
      temp,
      overrides: [
        timelineObjectsProvider.overrideWith(
          (ref) => const [
            KbFile(name: 'Third Age.unearth', relativePath: 'Third Age.unearth'),
          ],
        ),
      ],
    );
    final kb = container.read(kbSessionProvider)!.kb;

    await tester.runAsync(() async {
      await kb.createObject(
        name: 'Third Age',
        seed: const Timeline(
          id: 'tl-1',
          title: 'Third Age',
          items: [
            TimelineEventItem(
              id: 'fall',
              title: 'The bridge falls',
              year: 1825,
              mainDocumentPath: 'Places/Aldenmoor.md',
            ),
          ],
        ).toJson(),
      );
      await container.read(kbControllerProvider.notifier).refreshTree();
    });

    container.read(viewProvider.notifier).state = DsView.timelines;
    await pumpDsShell(tester, container);
    return container;
  }

  /// The pane header shows the open timeline's name, which can be the same
  /// word as a tab. Aim at the strip.
  Finder tab(String label) => find.descendant(
    of: find.byKey(const Key('timeline-reader-tabs')),
    matching: find.text(label),
  );

  /// Switches to the Timelines half of the pane.
  Future<void> showTimelines(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.tap(tab('Timelines'));
    await tester.pumpAndSettle();
  }

  /// Lets the debounced save fall due and land, so a test that edited does not
  /// end with a timer still pending.
  Future<void> settleSaves(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => container.read(openTimelineProvider.notifier).flush(),
    );
  }

  Future<void> openThirdAge(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.tap(find.byKey(const Key('timeline-row-Third Age.unearth')));
    await tester.runAsync(
      () => container
          .read(openTimelineProvider.notifier)
          .open('Third Age.unearth'),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the view places its own workspace and its own pane', (
    tester,
  ) async {
    await timelinesView(tester);

    expect(find.byKey(const Key('centre-workspace')), findsOneWidget);
    expect(find.byKey(const Key('timeline-reader-pane')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-base-pane')), findsNothing);
    expect(find.byKey(const Key('timeline-map-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timeline-strip')), findsOneWidget);
  });

  testWidgets('the segmented control switches what the pane is for', (
    tester,
  ) async {
    final container = await timelinesView(tester);

    // Description is what the pane opens on.
    expect(find.text('Select an event or an age on the timeline.'),
        findsOneWidget);
    expect(find.byKey(const Key('timeline-objects-list')), findsNothing);

    await showTimelines(tester, container);

    expect(find.byKey(const Key('timeline-objects-list')), findsOneWidget);
    expect(find.text('Third Age'), findsWidgets);
  });

  testWidgets('choosing a timeline puts it on the track', (tester) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    expect(container.read(openTimelineProvider)!.relativePath,
        'Third Age.unearth');
    expect(find.text('The bridge falls'), findsWidgets);
  });

  testWidgets('selecting an event reads its document, without moving the '
      'editor', (tester) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    container.read(selectedTimelineItemIdProvider.notifier).state = 'fall';
    // Read while the Timelines half is still showing, so the document is
    // fetched in real async before anything in the tree is watching for it.
    await tester.runAsync(
      () => container.read(timelineReaderDocumentProvider.future),
    );
    await tester.tap(tab('Detail'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('timeline-reader-description')),
        findsOneWidget);
    expect(find.text('Aldenmoor'), findsWidgets);
    // The Editor view is untouched: reading here is not opening there.
    expect(container.read(documentControllerProvider), isNull);
  });

  testWidgets('the centre is the map, and stays the map', (tester) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    // Nothing selects, expands or edits its way into the centre slot: the map
    // is what the centre is for.
    expect(find.byKey(const Key('timeline-map-canvas')), findsOneWidget);
    expect(find.byKey(const Key('timeline-item-editor')), findsOneWidget);
    expect(find.byKey(const Key('timeline-strip')), findsOneWidget);
  });

  testWidgets('choosing a timeline puts its first item in the editor', (
    tester,
  ) async {
    final container = await timelinesView(tester);

    // Nothing open yet, so there is nothing to edit and the pane says so.
    expect(find.text('No timeline open.'), findsOneWidget);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    // Choosing a timeline is already a choice of what to work on: the earliest
    // thing on it is selected, without a second click on the track.
    expect(container.read(selectedTimelineItemIdProvider), 'fall');
    expect(find.byKey(const Key('timeline-item-editor')), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'The bridge falls'),
      findsOneWidget,
    );
  });

  testWidgets('the left pane edits the selected item', (tester) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    await tester.enterText(find.byKey(const Key('timeline-item-year')), '1899');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('timeline-item-month')), '7');
    await tester.pumpAndSettle();

    final item = container.read(selectedTimelineItemProvider)!;
    expect(item.year, 1899);
    expect(item.month, 7);

    await settleSaves(tester, container);
  });

  testWidgets('emptying the month dates the item to the year alone', (
    tester,
  ) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    await tester.enterText(find.byKey(const Key('timeline-item-month')), '5');
    await tester.pumpAndSettle();
    expect(container.read(selectedTimelineItemProvider)!.month, 5);

    await tester.enterText(find.byKey(const Key('timeline-item-month')), '');
    await tester.pumpAndSettle();
    expect(container.read(selectedTimelineItemProvider)!.month, isNull);

    await settleSaves(tester, container);
  });

  testWidgets('a nation is named once and worn by the items', (tester) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    final actions = container.read(timelineActionControllerProvider);
    final nation = actions.addNation('The Vale')!;
    await tester.pumpAndSettle();

    // Named from an item, so it is already on that item.
    expect(container.read(selectedTimelineItemProvider)!.nationIds, isEmpty);
    actions.toggleNationOnItem(
      container.read(selectedTimelineItemProvider)!,
      nation.id,
    );
    await tester.pumpAndSettle();
    expect(
      container.read(selectedTimelineItemProvider)!.nationIds,
      [nation.id],
    );

    // Renaming is one edit, not one per item.
    actions.updateNation(nation.copyWith(name: 'The High Vale'));
    await tester.pumpAndSettle();
    expect(find.text('The High Vale'), findsWidgets);

    // Removing takes it off the items too, so no id is left unanswered.
    actions.removeNation(nation.id);
    await tester.pumpAndSettle();
    expect(container.read(selectedTimelineItemProvider)!.nationIds, isEmpty);

    await settleSaves(tester, container);
  });

  testWidgets('the first document connected becomes the main one', (
    tester,
  ) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);
    await openThirdAge(tester, container);

    final actions = container.read(timelineActionControllerProvider);
    var item = container.read(selectedTimelineItemProvider)!;
    expect(item.mainDocumentPath, 'Places/Aldenmoor.md');

    actions.linkDocument(item, 'Characters/Aldric.md');
    await tester.pumpAndSettle();
    item = container.read(selectedTimelineItemProvider)!;
    expect(item.mainDocumentPath, 'Places/Aldenmoor.md');
    expect(item.documentPaths, ['Characters/Aldric.md']);

    // Dropping the main one promotes another rather than leaving the reader
    // with nothing while a document is still connected.
    actions.unlinkDocument(item, 'Places/Aldenmoor.md');
    await tester.pumpAndSettle();
    item = container.read(selectedTimelineItemProvider)!;
    expect(item.mainDocumentPath, 'Characters/Aldric.md');
    expect(item.documentPaths, isEmpty);

    await settleSaves(tester, container);
  });

  testWidgets('a new timeline is created and opened', (tester) async {
    final container = await timelinesView(tester);

    await showTimelines(tester, container);

    await tester.runAsync(() async {
      final path = await container
          .read(kbControllerProvider.notifier)
          .createObject(name: kNewTimelineName, seed: newTimelineSeed());
      await container.read(openTimelineProvider.notifier).open(path);
    });
    await tester.pumpAndSettle();

    final open = container.read(openTimelineProvider)!;
    expect(open.relativePath, 'New timeline.unearth');
    expect(open.timeline.items, hasLength(2));
  });
}
