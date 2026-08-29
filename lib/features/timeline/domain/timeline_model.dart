/// Domain models for the Timeline feature in DaySeven.
library;

import 'package:dayseven/shared/blocks/custom_section.dart';

/// An item on the timeline: either a point event or a period/span.
sealed class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.title,
    required this.startYear,
    required this.startDateLabel,
    this.description = '',
    this.kbDocumentPath,
  });

  final String id;
  final String title;
  final double startYear;
  final String startDateLabel;
  final String description;
  final String? kbDocumentPath;

  bool get isPeriod;

  /// Whether this item links to a Knowledge Base document.
  bool get isDocumentLink =>
      kbDocumentPath != null && kbDocumentPath!.trim().isNotEmpty;

  TimelineItem copyWith({
    String? id,
    String? title,
    double? startYear,
    String? startDateLabel,
    String? description,
    String? kbDocumentPath,
    bool clearKbDocumentPath = false,
  });
}

/// A point milestone occurring at a single point in time.
class TimelineEventItem extends TimelineItem {
  const TimelineEventItem({
    required super.id,
    required super.title,
    required super.startYear,
    required super.startDateLabel,
    super.description,
    super.kbDocumentPath,
  });

  @override
  bool get isPeriod => false;

  @override
  TimelineEventItem copyWith({
    String? id,
    String? title,
    double? startYear,
    String? startDateLabel,
    String? description,
    String? kbDocumentPath,
    bool clearKbDocumentPath = false,
  }) => TimelineEventItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startYear: startYear ?? this.startYear,
    startDateLabel: startDateLabel ?? this.startDateLabel,
    description: description ?? this.description,
    kbDocumentPath: clearKbDocumentPath
        ? null
        : (kbDocumentPath ?? this.kbDocumentPath),
  );
}

/// A period/epoch spanning between start and resolution.
class TimelinePeriodItem extends TimelineItem {
  const TimelinePeriodItem({
    required super.id,
    required super.title,
    required super.startYear,
    required super.startDateLabel,
    required this.endYear,
    required this.endDateLabel,
    super.description,
    super.kbDocumentPath,
  });

  final double endYear;
  final String endDateLabel;

  @override
  bool get isPeriod => true;

  @override
  TimelinePeriodItem copyWith({
    String? id,
    String? title,
    double? startYear,
    String? startDateLabel,
    double? endYear,
    String? endDateLabel,
    String? description,
    String? kbDocumentPath,
    bool clearKbDocumentPath = false,
  }) => TimelinePeriodItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startYear: startYear ?? this.startYear,
    startDateLabel: startDateLabel ?? this.startDateLabel,
    endYear: endYear ?? this.endYear,
    endDateLabel: endDateLabel ?? this.endDateLabel,
    description: description ?? this.description,
    kbDocumentPath: clearKbDocumentPath
        ? null
        : (kbDocumentPath ?? this.kbDocumentPath),
  );
}

/// An encapsulated timeline section extracted from a [BlockDocument].
class TimelineSection extends CustomSection {
  const TimelineSection({
    required super.startIndex,
    required super.endIndex,
    required this.description,
    required this.items,
  });

  final String description;
  final List<TimelineItem> items;

  /// The earliest year among all items (defaults to 0 if empty).
  double get minYear {
    if (items.isEmpty) return 0;
    var min = items.first.startYear;
    for (final item in items) {
      if (item.startYear < min) min = item.startYear;
    }
    return min;
  }

  /// The latest year among all items (defaults to 100 if empty).
  double get maxYear {
    if (items.isEmpty) return 100;
    var max = items.first.startYear;
    for (final item in items) {
      final y = item is TimelinePeriodItem ? item.endYear : item.startYear;
      if (y > max) max = y;
    }
    return max;
  }

  TimelineSection copyWith({
    int? startIndex,
    int? endIndex,
    String? description,
    List<TimelineItem>? items,
  }) => TimelineSection(
    startIndex: startIndex ?? this.startIndex,
    endIndex: endIndex ?? this.endIndex,
    description: description ?? this.description,
    items: items ?? this.items,
  );
}
