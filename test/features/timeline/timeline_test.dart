/// The `.unearth` timeline format: what it writes, and what it survives being
/// handed.
library;

import 'package:dayseven/features/timeline/domain/timeline.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Timeline sample() => Timeline(
    id: 'tl-1',
    title: 'Third Age',
    description: 'The long peace.',
    items: [
      const TimelinePeriodItem(
        id: 'a',
        title: 'Rise of the North',
        startYear: 1800,
        startDateLabel: '1800',
        endYear: 1850,
        endDateLabel: '1850',
        color: TimelineColor.amber,
        documentPath: 'Places/North.md',
      ),
      const TimelineEventItem(
        id: 'b',
        title: 'The bridge falls',
        startYear: 1825,
        startDateLabel: '1825',
        description: 'It fell.',
      ),
    ],
  );

  group('round trip', () {
    test('a timeline survives being written and read back', () {
      final restored = Timeline.fromJson(sample().toJson());

      expect(restored.id, 'tl-1');
      expect(restored.title, 'Third Age');
      expect(restored.description, 'The long peace.');
      expect(restored.items, hasLength(2));

      final period = restored.items.first as TimelinePeriodItem;
      expect(period.title, 'Rise of the North');
      expect(period.endYear, 1850);
      expect(period.color, TimelineColor.amber);
      expect(period.documentPath, 'Places/North.md');

      final event = restored.items.last as TimelineEventItem;
      expect(event.startYear, 1825);
      expect(event.description, 'It fell.');
      expect(event.isDocumentLink, isFalse);
    });

    test('the envelope names the kind and the version', () {
      final json = sample().toJson();
      expect(json['kind'], 'timeline');
      expect(json['version'], 1);
    });

    test('an item with no link does not write an empty one', () {
      final json = sample().toJson();
      final event = (json['items']! as List).last as Map<String, Object?>;
      expect(event.containsKey('document'), isFalse);
    });
  });

  group('reading a file this app did not write', () {
    test('another kind is refused rather than read as a timeline', () {
      expect(
        () => Timeline.fromJson({'kind': 'map', 'version': 1}),
        throwsA(isA<TimelineFormatException>()),
      );
    });

    test('a newer format is refused rather than saved back stripped', () {
      expect(
        () => Timeline.fromJson({'kind': 'timeline', 'version': 2}),
        throwsA(isA<TimelineFormatException>()),
      );
    });

    test('a file with no items reads as an empty timeline', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 1,
        'title': 'Empty',
      });
      expect(timeline.items, isEmpty);
      expect(timeline.minYear, Timeline.emptyMinYear);
      expect(timeline.maxYear, Timeline.emptyMaxYear);
    });

    test('hand-edited items come back in order', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 1,
        'items': [
          {'id': 'late', 'type': 'event', 'start': 1900},
          {'id': 'early', 'type': 'event', 'start': 1700},
        ],
      });
      expect(timeline.items.map((i) => i.id), ['early', 'late']);
    });

    test('a period ending before it starts is tidied, not refused', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 1,
        'items': [
          {'id': 'a', 'type': 'period', 'start': 1800, 'end': 1700},
        ],
      });
      final period = timeline.items.single as TimelinePeriodItem;
      expect(period.endYear, greaterThan(period.startYear));
    });

    test('an item with no id is refused: nothing could select it', () {
      expect(
        () => Timeline.fromJson({
          'kind': 'timeline',
          'version': 1,
          'items': [
            {'type': 'event', 'start': 1800},
          ],
        }),
        throwsA(isA<TimelineFormatException>()),
      );
    });
  });

  group('span', () {
    test('maxYear counts where a period ends, not where it starts', () {
      expect(sample().maxYear, 1850);
      expect(sample().minYear, 1800);
    });
  });

  group('parseYearLabel', () {
    test('reads a bare year', () {
      expect(parseYearLabel('1803'), 1803);
    });

    test('reads an invented calendar with more months than ours', () {
      final scalar = parseYearLabel('20 Month 13, Year 1803');
      expect(scalar, greaterThan(1803));
      expect(scalar, lessThan(1805));
    });

    test('reads BCE as a negative year', () {
      expect(parseYearLabel('500 BCE'), -500);
    });

    test('returns null when there is no number to find', () {
      expect(parseYearLabel('long ago'), isNull);
      expect(parseYearLabel('   '), isNull);
    });
  });
}
