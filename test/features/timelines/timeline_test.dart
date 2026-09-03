/// The `.unearth` timeline format: what it writes, and what it survives being
/// handed.
library;

import 'package:dayseven/features/timelines/domain/timeline.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Timeline sample() => const Timeline(
    id: 'tl-1',
    title: 'Third Age',
    description: 'The long peace.',
    nations: [
      TimelineNation(id: 'n1', name: 'The Vale', color: TimelineColor.teal),
      TimelineNation(id: 'n2', name: 'The North', color: TimelineColor.amber),
    ],
    items: [
      TimelinePeriodItem(
        id: 'a',
        title: 'Rise of the North',
        year: 1800,
        endYear: 1850,
        color: TimelineColor.amber,
        mainDocumentPath: 'Places/North.md',
        documentPaths: ['Characters/Aldric.md'],
        nationIds: ['n2'],
      ),
      TimelineEventItem(
        id: 'b',
        title: 'The bridge falls',
        year: 1842,
        month: 3,
        description: 'It fell.',
        nationIds: ['n1', 'n2'],
      ),
    ],
  );

  group('round trip', () {
    test('a timeline survives being written and read back', () {
      final restored = Timeline.fromJson(sample().toJson());

      expect(restored.id, 'tl-1');
      expect(restored.title, 'Third Age');
      expect(restored.nations.map((n) => n.name), ['The Vale', 'The North']);

      final period = restored.items.first as TimelinePeriodItem;
      expect(period.year, 1800);
      expect(period.endYear, 1850);
      expect(period.color, TimelineColor.amber);
      expect(period.mainDocumentPath, 'Places/North.md');
      expect(period.documentPaths, ['Characters/Aldric.md']);
      expect(period.allDocumentPaths, [
        'Places/North.md',
        'Characters/Aldric.md',
      ]);
      expect(period.nationIds, ['n2']);

      final event = restored.items.last as TimelineEventItem;
      expect(event.year, 1842);
      expect(event.month, 3);
      expect(event.description, 'It fell.');
      expect(event.hasMainDocument, isFalse);
      expect(event.nationIds, ['n1', 'n2']);
    });

    test('the envelope names the kind and the version', () {
      final json = sample().toJson();
      expect(json['kind'], 'timeline');
      expect(json['version'], 3);
    });

    test('absent values are left out rather than written as null', () {
      final json = sample().toJson();
      final event = (json['items']! as List).last as Map<String, Object?>;
      expect(event.containsKey('document'), isFalse);
      expect(event.containsKey('documents'), isFalse);

      final period = (json['items']! as List).first as Map<String, Object?>;
      expect(period.containsKey('month'), isFalse);
    });
  });

  group('reading a version 1 file', () {
    Map<String, Object?> v1() => {
      'kind': 'timeline',
      'version': 1,
      'id': 'old',
      'title': 'Second Age',
      'items': [
        {
          'id': 'a',
          'type': 'period',
          'title': 'The long war',
          'start': 1800.5,
          'startLabel': '1800',
          'end': 1850.0,
          'endLabel': '1850',
          'color': 'teal',
          'document': 'Places/North.md',
        },
      ],
    };

    test('a scalar date becomes the year it fell in', () {
      final timeline = Timeline.fromJson(v1());
      final item = timeline.items.single as TimelinePeriodItem;

      expect(item.year, 1800);
      expect(item.endYear, 1850);
      // Version 1 never recorded a month, so none is invented.
      expect(item.month, isNull);
    });

    test("version 1's single link becomes the main document", () {
      final item = Timeline.fromJson(v1()).items.single;
      expect(item.mainDocumentPath, 'Places/North.md');
      expect(item.documentPaths, isEmpty);
    });

    test('it is written back at the current version', () {
      final upgraded = Timeline.fromJson(v1()).toJson();
      expect(upgraded['version'], 3);
    });
  });

  group('reading a file this app did not write', () {
    test('another kind is refused rather than read as a timeline', () {
      expect(
        () => Timeline.fromJson({'kind': 'map', 'version': 3}),
        throwsA(isA<TimelineFormatException>()),
      );
    });

    test('a newer format is refused rather than saved back stripped', () {
      expect(
        () => Timeline.fromJson({'kind': 'timeline', 'version': 4}),
        throwsA(isA<TimelineFormatException>()),
      );
    });

    test('a file with no items reads as an empty timeline', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 3,
        'title': 'Empty',
      });
      expect(timeline.items, isEmpty);
      expect(timeline.minYear, Timeline.emptyMinYear);
      expect(timeline.maxYear, Timeline.emptyMaxYear);
    });

    test('hand-edited items come back in order', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 3,
        'items': [
          {'id': 'late', 'type': 'event', 'year': 1900},
          {'id': 'early', 'type': 'event', 'year': 1700},
        ],
      });
      expect(timeline.items.map((i) => i.id), ['early', 'late']);
    });

    test('an age ending before it starts is tidied, not refused', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 3,
        'items': [
          {'id': 'a', 'type': 'period', 'year': 1800, 'end': 1700},
        ],
      });
      final period = timeline.items.single as TimelinePeriodItem;
      expect(period.endYear, greaterThan(period.year));
    });

    test('an item with no id is refused: nothing could select it', () {
      expect(
        () => Timeline.fromJson({
          'kind': 'timeline',
          'version': 3,
          'items': [
            {'type': 'event', 'year': 1800},
          ],
        }),
        throwsA(isA<TimelineFormatException>()),
      );
    });

    test('a nation nothing defines is dropped from the items', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 3,
        'nations': [
          {'id': 'n1', 'name': 'The Vale'},
        ],
        'items': [
          {
            'id': 'a',
            'type': 'event',
            'year': 1800,
            'nations': ['n1', 'ghost'],
          },
        ],
      });
      expect(timeline.items.single.nationIds, ['n1']);
    });

    test('a month of zero or below is no month at all', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 3,
        'items': [
          {'id': 'a', 'type': 'event', 'year': 1800, 'month': 0},
        ],
      });
      expect(timeline.items.single.month, isNull);
    });
  });

  group('the map', () {
    test('a timeline has none until one is uploaded', () {
      expect(sample().hasMap, isFalse);
      expect(sample().toJson().containsKey('map'), isFalse);
    });

    test('an asset id round-trips', () {
      final withMap = sample().copyWith(
        map: const TimelineMap(assetId: 'abc.png'),
      );
      final restored = Timeline.fromJson(withMap.toJson());

      expect(restored.hasMap, isTrue);
      expect(restored.map!.assetId, 'abc.png');
    });

    test('clearing it leaves the field out rather than writing null', () {
      final cleared = sample()
          .copyWith(map: const TimelineMap(assetId: 'abc.png'))
          .copyWith(clearMap: true);

      expect(cleared.hasMap, isFalse);
      expect(cleared.toJson().containsKey('map'), isFalse);
    });

    test('a map with no asset id is no map', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 3,
        'map': <String, Object?>{},
      });
      expect(timeline.hasMap, isFalse);
    });

    test('a version 1 file simply has no map', () {
      final timeline = Timeline.fromJson({
        'kind': 'timeline',
        'version': 1,
        'items': <Object?>[],
      });
      expect(timeline.hasMap, isFalse);
    });
  });

  group('placing an item on the track', () {
    test('a month sets it between one year mark and the next', () {
      const timeline = Timeline(id: 't', title: 'T');
      const item = TimelineEventItem(id: 'a', title: '', year: 1800, month: 7);

      final at = timeline.plotStart(item);
      expect(at, greaterThan(1800));
      expect(at, lessThan(1801));
    });

    test('a thirteenth month stays inside its own year', () {
      const timeline = Timeline(id: 't', title: 'T', monthsPerYear: 13);
      const item = TimelineEventItem(id: 'a', title: '', year: 1800, month: 13);

      expect(timeline.plotStart(item), lessThan(1801));
    });

    test('no month is the year itself', () {
      const timeline = Timeline(id: 't', title: 'T');
      const item = TimelineEventItem(id: 'a', title: '', year: 1800);
      expect(timeline.plotStart(item), 1800);
    });

    test('maxYear counts where an age ends, not where it starts', () {
      expect(sample().maxYear, 1850);
      expect(sample().minYear, 1800);
    });
  });

  group('nations', () {
    test('are listed in the timeline order, not the item order', () {
      final timeline = sample();
      final event = timeline.items.last;
      // The item says n1 then n2; the timeline defines them in that order too,
      // so two items can never show the same pair differently.
      expect(
        timeline.nationsOf(event).map((n) => n.name),
        ['The Vale', 'The North'],
      );
    });
  });

  group('dateLabel', () {
    const timeline = Timeline(id: 't', title: 'T');

    test('a year on its own', () {
      expect(
        timeline.dateLabel(
          const TimelineEventItem(id: 'a', title: '', year: 1842),
        ),
        '1842',
      );
    });

    test('a month is said as a number, having no name', () {
      expect(
        timeline.dateLabel(
          const TimelineEventItem(id: 'a', title: '', year: 1842, month: 3),
        ),
        'Month 3, 1842',
      );
    });

    test('an age reads as a span', () {
      expect(
        timeline.dateLabel(
          const TimelinePeriodItem(
            id: 'a',
            title: '',
            year: 1800,
            endYear: 1850,
          ),
        ),
        '1800 → 1850',
      );
    });
  });
}
