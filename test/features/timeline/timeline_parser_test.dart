import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/features/timeline/domain/timeline_parser.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/markdown.dart';

void main() {
  group('TimelineParser', () {
    const parser = TimelineParser();

    test('parses a timeline chunk with periods, events, desc, and links', () {
      const markdown = '''
---
d7: 1
schema: 1
id: "test-doc-1"
title: "History of Aldenmoor"
---

<!-- d7 h1 -->
# History of Aldenmoor

<!-- d7 p1 -->
Introductory paragraph about the kingdom.

<!-- d7 h2 -->
# Timeline

<!-- d7 p2 -->
<timeline_desc>The Third Age of Aldenmoor and the northern expansion.</timeline_desc>

<!-- d7 h3 -->
### New age

<!-- d7 p3 -->
**20 Month 13, Year 1803 → 13 Month 1, Year 1874**

<!-- d7 p4 -->
A prolonged period of cultural and technological advancement.

<!-- d7 h4 -->
### The High Treaty

<!-- d7 p5 -->
**10 Month 5, Year 1920**

<!-- d7 p6 -->
[Characters/Aldric.md](Characters/Aldric.md)

<!-- d7 h5 -->
# Timeline

<!-- d7 p7 -->
Outro paragraph after the timeline.
''';

      final doc = decodeMarkdown(markdown);
      final section = parser.findFirst(doc);

      expect(section, isNotNull);
      expect(
        section!.description,
        'The Third Age of Aldenmoor and the northern expansion.',
      );
      expect(section.items.length, 2);

      // Period item
      final period = section.items[0] as TimelinePeriodItem;
      expect(period.title, 'New age');
      expect(period.startDateLabel, '20 Month 13, Year 1803');
      expect(period.endDateLabel, '13 Month 1, Year 1874');
      expect(period.startYear, closeTo(1804.0, 1.0));
      expect(period.endYear, closeTo(1874.0, 1.0));
      expect(
        period.description,
        'A prolonged period of cultural and technological advancement.',
      );
      expect(period.isPeriod, isTrue);
      expect(period.isDocumentLink, isFalse);

      // Event item with link
      final event = section.items[1] as TimelineEventItem;
      expect(event.title, 'The High Treaty');
      expect(event.startDateLabel, '10 Month 5, Year 1920');
      expect(event.startYear, closeTo(1920.35, 1.0));
      expect(event.isPeriod, isFalse);
      expect(event.isDocumentLink, isTrue);
      expect(event.kbDocumentPath, 'Characters/Aldric.md');
    });

    test('serializes and replaces timeline section in BlockDocument', () {
      final initialDoc = const BlockDocument(
        id: 'doc-1',
        title: 'Timeline Test',
        blocks: [
          ParagraphBlock(id: 'p1', spans: [TextSpanNode(text: 'Before')]),
        ],
      );

      final newSection = TimelineSection(
        startIndex: 1,
        endIndex: 1,
        description: 'Epic saga',
        items: [
          const TimelineEventItem(
            id: 'evt-1',
            title: 'Founding',
            startYear: 1000,
            startDateLabel: 'Year 1000',
            description: 'The city was founded.',
          ),
          const TimelinePeriodItem(
            id: 'per-1',
            title: 'Golden Era',
            startYear: 1050,
            startDateLabel: 'Year 1050',
            endYear: 1150,
            endDateLabel: 'Year 1150',
            kbDocumentPath: 'Places/Citadel.md',
          ),
        ],
      );

      final updatedDoc = parser.insertSection(initialDoc, newSection);
      expect(updatedDoc.blocks.length, greaterThan(2));

      // Parse back
      final parsed = parser.findFirst(updatedDoc);
      expect(parsed, isNotNull);
      expect(parsed!.description, 'Epic saga');
      expect(parsed.items.length, 2);
      expect(parsed.items[0].title, 'Founding');
      expect(parsed.items[1].title, 'Golden Era');
      expect(parsed.items[1].kbDocumentPath, 'Places/Citadel.md');
    });
  });
}
