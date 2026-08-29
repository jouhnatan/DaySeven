/// Domain models for the Timeline feature in DaySeven.
library;

import 'package:dayseven/shared/blocks/custom_section.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// An item on the timeline: either a point event or a period/span.
sealed class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.title,
    required this.startYear,
    required this.startDateLabel,
    this.color = TimelineColor.fern,
    this.description = '',
    this.kbDocumentPath,
  });

  final String id;
  final String title;
  final double startYear;
  final String startDateLabel;
  final TimelineColor color;
  final String description;
  final String? kbDocumentPath;

  bool get isPeriod;

  /// Whether this item links to a Knowledge Base document.
  bool get isDocumentLink =>
      kbDocumentPath != null && kbDocumentPath!.trim().isNotEmpty;

  /// Converts this item into a period duration stretching over time.
  TimelinePeriodItem toPeriod({
    double? endYear,
    String? endDateLabel,
  }) {
    final end = endYear ?? (startYear + 20.0);
    final endLabel = endDateLabel ?? '${end.toInt()}';
    return TimelinePeriodItem(
      id: id,
      title: title,
      startYear: startYear,
      startDateLabel: startDateLabel,
      endYear: end,
      endDateLabel: endLabel,
      color: color,
      description: description,
      kbDocumentPath: kbDocumentPath,
    );
  }

  /// Converts this item into a point event.
  TimelineEventItem toPoint() {
    return TimelineEventItem(
      id: id,
      title: title,
      startYear: startYear,
      startDateLabel: startDateLabel,
      color: color,
      description: description,
      kbDocumentPath: kbDocumentPath,
    );
  }

  TimelineItem copyWith({
    String? id,
    String? title,
    double? startYear,
    String? startDateLabel,
    TimelineColor? color,
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
    super.color = TimelineColor.fern,
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
    TimelineColor? color,
    String? description,
    String? kbDocumentPath,
    bool clearKbDocumentPath = false,
  }) => TimelineEventItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startYear: startYear ?? this.startYear,
    startDateLabel: startDateLabel ?? this.startDateLabel,
    color: color ?? this.color,
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
    super.color = TimelineColor.fern,
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
    TimelineColor? color,
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
    color: color ?? this.color,
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

  /// The earliest year among all items (defaults to 1800 if empty).
  double get minYear {
    if (items.isEmpty) return 1800;
    var min = items.first.startYear;
    for (final item in items) {
      if (item.startYear < min) min = item.startYear;
    }
    return min;
  }

  /// The latest year among all items (defaults to 1850 if empty).
  double get maxYear {
    if (items.isEmpty) return 1850;
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
