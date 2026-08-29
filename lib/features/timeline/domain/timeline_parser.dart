/// Parser and serializer for Timeline sections in DaySeven documents.
library;

import 'package:uuid/uuid.dart';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/custom_section.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';

const Uuid _uuid = Uuid();

class TimelineParser extends CustomSectionParser<TimelineSection> {
  const TimelineParser({super.sectionHeader = 'Timeline'});

  @override
  TimelineSection? findFirst(BlockDocument document) {
    final sections = parseAll(document);
    return sections.isEmpty ? null : sections.first;
  }

  @override
  List<TimelineSection> parseAll(BlockDocument document) {
    final sections = <TimelineSection>[];
    final blocks = document.blocks;
    var i = 0;

    while (i < blocks.length) {
      final block = blocks[i];
      if (_isTimelineHeader(block)) {
        final startIndex = i;
        i++;
        var endIndex = -1;

        // Look for the closing # Timeline header
        while (i < blocks.length) {
          if (_isTimelineHeader(blocks[i])) {
            endIndex = i;
            break;
          }
          i++;
        }

        // If no closing header was found, encapsulate to the end of the document
        // or up to the next top-level heading.
        if (endIndex == -1) {
          endIndex = blocks.length - 1;
        }

        final innerBlocks = blocks.sublist(startIndex + 1, endIndex);
        final (description, items) = _parseInnerBlocks(innerBlocks);

        sections.add(
          TimelineSection(
            startIndex: startIndex,
            endIndex: endIndex,
            description: description,
            items: items,
          ),
        );
      }
      i++;
    }

    return sections;
  }

  bool _isTimelineHeader(Block block) {
    if (block is! HeadingBlock) return false;
    return block.plainText.trim().toLowerCase() == sectionHeader.toLowerCase();
  }

  (String, List<TimelineItem>) _parseInnerBlocks(List<Block> innerBlocks) {
    var description = '';
    final items = <TimelineItem>[];

    var i = 0;
    // 1. Check for <timeline_desc>...</timeline_desc>
    while (i < innerBlocks.length) {
      final block = innerBlocks[i];
      final text = block.plainText;
      final descMatch = RegExp(
        r'<timeline[_\-:]?desc>(.*?)(?:</timeline[_\-:]?desc>|$)',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(text);

      if (descMatch != null) {
        description = descMatch.group(1)?.trim() ?? '';
        i++;
      } else {
        break;
      }
    }

    // 2. Parse items (Heading3/Heading2 + date line + description/link line)
    String? currentTitle;
    String? currentItemId;
    String? currentDateLine;
    final contentLines = <String>[];
    String? currentLink;

    void flushItem() {
      if (currentTitle != null) {
        final title = currentTitle!;
        final dateLine = currentDateLine?.trim() ?? '';
        final desc = contentLines.join('\n').trim();
        final link = currentLink;

        final double fallbackYear = items.isEmpty
            ? 1800.0
            : (items.last is TimelinePeriodItem
                ? (items.last as TimelinePeriodItem).endYear + 10.0
                : items.last.startYear + 10.0);

        final item = _constructItem(
          id: currentItemId ?? _uuid.v7(),
          title: title,
          dateLine: dateLine,
          description: desc,
          link: link,
          fallbackYear: fallbackYear,
        );
        items.add(item);
      }
      currentTitle = null;
      currentItemId = null;
      currentDateLine = null;
      contentLines.clear();
      currentLink = null;
    }

    while (i < innerBlocks.length) {
      final block = innerBlocks[i];

      // A subheading (level 2-4) begins a timeline item
      if (block is HeadingBlock && block.level >= 2 && block.level <= 4) {
        flushItem();
        currentTitle = block.plainText.trim();
        currentItemId = block.id;
      } else if (currentTitle != null) {
        // Look for links in spans
        if (block is TextBlock) {
          for (final span in block.spans) {
            if (span.href != null && span.href!.isNotEmpty) {
              currentLink = span.href;
            }
          }
        }

        final plain = block.plainText.trim();
        if (plain.isNotEmpty && !plain.startsWith('<timeline_desc>')) {
          if (currentDateLine == null) {
            // The first non-empty block under the item heading is ALWAYS the date line
            currentDateLine = plain;
          } else {
            // Subsequent blocks under the heading are description lines
            contentLines.add(plain);
          }
        }
      }
      i++;
    }
    flushItem();

    return (description, items);
  }

  TimelineItem _constructItem({
    required String id,
    required String title,
    required String dateLine,
    required String description,
    required String? link,
    required double fallbackYear,
  }) {
    final colorMatch = RegExp(
      r'<!--\s*color:?\s*([a-zA-Z]+)\s*-->|\|\s*([a-zA-Z]+)',
    ).firstMatch(dateLine);
    final colorId = colorMatch?.group(1) ?? colorMatch?.group(2);
    final color = TimelineColor.fromId(colorId);

    final cleanDate = dateLine
        .replaceAll(RegExp(r'<!--.*?-->'), '')
        .replaceAll(RegExp(r'\|.*$'), '')
        .replaceAll('*', '')
        .trim();
    final isRange = cleanDate.contains('→') || cleanDate.contains('->');

    if (isRange) {
      final parts = cleanDate.contains('→')
          ? cleanDate.split('→')
          : cleanDate.split('->');
      final startLabel = parts.first.trim();
      final endLabel = parts.length > 1 ? parts[1].trim() : '';

      final startYear = parseDateScalar(startLabel) ?? fallbackYear;
      final endYear = parseDateScalar(endLabel) ?? (startYear + 10);

      return TimelinePeriodItem(
        id: id,
        title: title,
        startYear: startYear,
        startDateLabel: startLabel.isEmpty ? '${startYear.toInt()}' : startLabel,
        endYear: endYear,
        endDateLabel: endLabel.isEmpty ? '${endYear.toInt()}' : endLabel,
        color: color,
        description: description,
        kbDocumentPath: link,
      );
    } else {
      final startYear = parseDateScalar(cleanDate) ?? fallbackYear;
      return TimelineEventItem(
        id: id,
        title: title,
        startYear: startYear,
        startDateLabel: cleanDate.isEmpty ? '${startYear.toInt()}' : cleanDate,
        color: color,
        description: description,
        kbDocumentPath: link,
      );
    }
  }

  /// Parses numeric year coordinates from a date string.
  /// Handles "20 Month 13, Year 1803", "1803-13-20", "Year 1803", "1803", "500 BCE", etc.
  static double? parseDateScalar(String raw) {
    final text = raw.replaceAll('*', '').trim();
    if (text.isEmpty) return null;

    final isBce = RegExp(r'\b(bce|bc)\b', caseSensitive: false).hasMatch(text);

    // 1. Check for Year <number> (e.g. "Year 1803", "Year 1803.5", "Year -500")
    final yearMatch = RegExp(r'Year\s+(-?\d+(?:\.\d+)?)', caseSensitive: false)
        .firstMatch(text);
    final monthMatch = RegExp(r'Month\s+(\d+)', caseSensitive: false)
        .firstMatch(text);
    final dayMatch = RegExp(r'(\d+)\s+Month', caseSensitive: false)
        .firstMatch(text);

    if (yearMatch != null) {
      final y = double.tryParse(yearMatch.group(1)!);
      if (y != null) {
        var scalar = y;
        if (monthMatch != null) {
          final m = double.tryParse(monthMatch.group(1)!) ?? 1;
          scalar += ((m - 1).clamp(0, 20) / 12);
        }
        if (dayMatch != null) {
          final d = double.tryParse(dayMatch.group(1)!) ?? 1;
          scalar += (d.clamp(0, 31) / 365);
        }
        return isBce && scalar > 0 ? -scalar : scalar;
      }
    }

    // 2. Check for ISO or YYYY-MM-DD or YYYY/MM/DD
    final isoMatch = RegExp(r'^(-?\d{1,6})(?:[-/](\d{1,2}))?(?:[-/](\d{1,2}))?')
        .firstMatch(text);
    if (isoMatch != null) {
      final y = double.tryParse(isoMatch.group(1)!);
      if (y != null) {
        var scalar = y;
        final m = double.tryParse(isoMatch.group(2) ?? '');
        final d = double.tryParse(isoMatch.group(3) ?? '');
        if (m != null) scalar += ((m - 1) / 12);
        if (d != null) scalar += (d / 365);
        return isBce && scalar > 0 ? -scalar : scalar;
      }
    }

    // 3. Fallback to any number in string
    final numMatch = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(text);
    if (numMatch != null) {
      final y = double.tryParse(numMatch.group(1)!);
      if (y != null) {
        return isBce && y > 0 ? -y : y;
      }
    }

    return null;
  }

  @override
  List<Block> serializeSection(TimelineSection section) {
    final blocks = <Block>[];

    // Opening # Timeline
    blocks.add(
      HeadingBlock(
        id: _uuid.v7(),
        level: 1,
        spans: [const TextSpanNode(text: 'Timeline')],
      ),
    );

    // <timeline_desc>
    if (section.description.isNotEmpty) {
      blocks.add(
        ParagraphBlock(
          id: _uuid.v7(),
          spans: [
            TextSpanNode(
              text: '<timeline_desc>${section.description}</timeline_desc>',
            ),
          ],
        ),
      );
    }

    // Items
    for (final item in section.items) {
      // Heading3 for item title
      blocks.add(
        HeadingBlock(
          id: item.id.isNotEmpty ? item.id : _uuid.v7(),
          level: 3,
          spans: [TextSpanNode(text: item.title)],
        ),
      );

      // Date paragraph (bold) with optional color tag
      final dateText = item is TimelinePeriodItem
          ? '${item.startDateLabel} → ${item.endDateLabel}'
          : item.startDateLabel;
      final colorTag = item.color != TimelineColor.fern
          ? ' <!-- color:${item.color.id} -->'
          : '';

      blocks.add(
        ParagraphBlock(
          id: _uuid.v7(),
          spans: [
            TextSpanNode(
              text: '$dateText$colorTag',
              bold: true,
            ),
          ],
        ),
      );

      // Description or KB hyperlink
      if (item.isDocumentLink) {
        blocks.add(
          ParagraphBlock(
            id: _uuid.v7(),
            spans: [
              TextSpanNode(
                text: item.kbDocumentPath!,
                href: item.kbDocumentPath!,
              ),
            ],
          ),
        );
      } else if (item.description.isNotEmpty) {
        blocks.add(
          ParagraphBlock(
            id: _uuid.v7(),
            spans: [TextSpanNode(text: item.description)],
          ),
        );
      }
    }

    // Closing # Timeline
    blocks.add(
      HeadingBlock(
        id: _uuid.v7(),
        level: 1,
        spans: [const TextSpanNode(text: 'Timeline')],
      ),
    );

    return blocks;
  }
}
