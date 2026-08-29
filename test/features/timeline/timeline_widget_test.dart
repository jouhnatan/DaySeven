import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/features/timeline/ui/timeline_inspector.dart';
import 'package:dayseven/features/timeline/ui/timeline_popover.dart';
import 'package:dayseven/features/timeline/ui/timeline_toolbar_button.dart';
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
  });
}
