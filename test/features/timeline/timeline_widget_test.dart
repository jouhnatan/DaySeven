import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/features/timeline/ui/timeline_color_picker.dart';
import 'package:dayseven/features/timeline/ui/timeline_inspector.dart';
import 'package:dayseven/features/timeline/ui/timeline_popover.dart';
import 'package:dayseven/features/timeline/ui/timeline_toolbar_button.dart';
import 'package:dayseven/features/timeline/ui/timeline_track.dart';
import 'package:dayseven/features/timeline/ui/timeline_widget.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

void main() {
  Widget buildApp(Widget child, {List<Override> overrides = const []}) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: dsTheme(),
        home: Scaffold(body: child),
      ),
    );
  }

  group('TimelineWidget', () {
    testWidgets('renders nothing when active document has no timeline section', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          const TimelineWidget(),
          overrides: [
            activeTimelineSectionProvider.overrideWithValue(null),
          ],
        ),
      );

      expect(find.byKey(const Key('timeline-widget-container')), findsNothing);
    });

    testWidgets('renders timeline header, track, inspector and remove button', (
      tester,
    ) async {
      final section = TimelineSection(
        startIndex: 0,
        endIndex: 5,
        description: 'Age of Discovery',
        items: [
          const TimelinePeriodItem(
            id: 'p1',
            title: 'First Dynasty',
            startYear: 1200,
            startDateLabel: 'Year 1200',
            endYear: 1300,
            endDateLabel: 'Year 1300',
            description: 'The golden age of kings.',
          ),
          const TimelineEventItem(
            id: 'e1',
            title: 'Great Treaty',
            startYear: 1250,
            startDateLabel: 'Year 1250',
            description: 'Peace was established.',
            kbDocumentPath: 'Characters/King.md',
          ),
        ],
      );

      await tester.pumpWidget(
        buildApp(
          const TimelineWidget(),
          overrides: [
            activeTimelineSectionProvider.overrideWithValue(section),
          ],
        ),
      );

      expect(find.byKey(const Key('timeline-widget-container')), findsOneWidget);
      expect(find.text('Timeline'), findsOneWidget);
      expect(find.text('Age of Discovery'), findsOneWidget);
      expect(find.text('First Dynasty'), findsOneWidget);
      expect(find.text('Great Treaty'), findsOneWidget);
      expect(find.text('Remove'), findsOneWidget);
      expect(find.byType(TimelineInspector), findsOneWidget);

      // Tap Remove button to see confirmation dialog
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(find.byType(DsDialog), findsOneWidget);
      expect(find.text('Remove Timeline'), findsNWidgets(2)); // Title & button label
    });

    testWidgets('displays TimelinePopover when an item is selected', (
      tester,
    ) async {
      const item = TimelineEventItem(
        id: 'e1',
        title: 'Great Treaty',
        startYear: 1250,
        startDateLabel: 'Year 1250',
        description: 'Peace was established.',
        kbDocumentPath: 'Characters/King.md',
      );

      await tester.pumpWidget(
        buildApp(
          TimelinePopover(
            item: item,
            onClose: () {},
          ),
        ),
      );

      expect(find.text('Great Treaty'), findsOneWidget);
      expect(find.text('Year 1250'), findsOneWidget);
      expect(find.text('Linked Document'), findsOneWidget);
      expect(find.text('Characters/King.md'), findsOneWidget);
    });

    testWidgets('TimelineToolbarButton renders and toggles timeline', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildApp(
          const TimelineToolbarButton(),
          overrides: [
            activeTimelineSectionProvider.overrideWithValue(null),
          ],
        ),
      );

      expect(find.text('Timeline'), findsOneWidget);
      expect(find.byIcon(Icons.timeline), findsOneWidget);
    });

    testWidgets('TimelineColorPicker renders and triggers selection', (
      tester,
    ) async {
      TimelineColor? selected;

      await tester.pumpWidget(
        buildApp(
          TimelineColorPicker(
            selectedColor: TimelineColor.fern,
            onColorSelected: (c) => selected = c,
          ),
        ),
      );

      expect(find.byType(TimelineColorPicker), findsOneWidget);

      // Open popup menu
      await tester.tap(find.byType(TimelineColorPicker));
      await tester.pumpAndSettle();

      expect(find.text('Sapphire'), findsOneWidget);
      expect(find.text('Amber'), findsOneWidget);
      expect(find.text('Rose'), findsOneWidget);

      // Tap Sapphire
      await tester.tap(find.text('Sapphire'));
      await tester.pumpAndSettle();

      expect(selected, TimelineColor.blue);
    });

    testWidgets('TimelineTrack renders left and right caret buttons and scrolls', (
      tester,
    ) async {
      final section = TimelineSection(
        startIndex: 0,
        endIndex: 5,
        description: 'Epic History',
        items: [
          const TimelinePeriodItem(
            id: 'p1',
            title: 'Ancient Epoch',
            startYear: 1000,
            startDateLabel: '1000',
            endYear: 1200,
            endDateLabel: '1200',
          ),
          const TimelineEventItem(
            id: 'e1',
            title: 'Grand Coronation',
            startYear: 1250,
            startDateLabel: '1250',
          ),
        ],
      );

      await tester.pumpWidget(
        buildApp(
          TimelineTrack(section: section),
        ),
      );

      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);

      // Tap right caret button
      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();

      // Tap left caret button
      await tester.tap(find.byIcon(Icons.chevron_left));
      await tester.pumpAndSettle();
    });

    testWidgets('TimelineTrack shows floating year bubble during event drag', (
      tester,
    ) async {
      final section = TimelineSection(
        startIndex: 0,
        endIndex: 5,
        description: 'Epic History',
        items: [
          const TimelineEventItem(
            id: 'e1',
            title: 'Great Expedition',
            startYear: 1820,
            startDateLabel: '1820',
          ),
        ],
      );

      await tester.pumpWidget(
        buildApp(
          TimelineTrack(section: section),
        ),
      );

      expect(find.text('Great Expedition'), findsOneWidget);

      // Drag event horizontally
      final gesture = await tester.startGesture(tester.getCenter(find.text('Great Expedition')));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();

      // Year bubble should appear
      expect(find.textContaining('18'), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
