/// A Timeline: an object of its own, stored as a `.unearth` file in the
/// Knowledge Base.
///
/// A timeline used to be a run of headings and paragraphs inside somebody's
/// document, which meant it could only exist if a document volunteered to host
/// it — a timeline covering ten places had to live inside one of them. It is
/// now a file of its own, and its items point outwards at documents instead.
///
/// The file is indented JSON on the user's disk, so it can be read and edited
/// without this app. That cuts both ways: nothing here may assume the file was
/// written by this version, and [Timeline.fromJson] is written to survive a
/// hand-edit that dropped a field or reordered the items.
library;

import 'package:dayseven/shared/ui/theme.dart';

/// Raised when a `.unearth` file cannot be read as a timeline.
class TimelineFormatException implements Exception {
  const TimelineFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// An item on the timeline: either a point event or a period/span.
sealed class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.title,
    required this.startYear,
    required this.startDateLabel,
    this.color = TimelineColor.fern,
    this.description = '',
    this.documentPath,
  });

  final String id;
  final String title;
  final double startYear;
  final String startDateLabel;
  final TimelineColor color;
  final String description;

  /// The Knowledge Base document this item stands for, if any. Relative to the
  /// Knowledge Base root, POSIX-style, exactly as `KbFile.relativePath` is.
  final String? documentPath;

  bool get isPeriod;

  /// Whether this item points at a Knowledge Base document.
  bool get isDocumentLink =>
      documentPath != null && documentPath!.trim().isNotEmpty;

  /// Converts this item into a period stretching over time.
  TimelinePeriodItem toPeriod({double? endYear, String? endDateLabel}) {
    final end = endYear ?? (startYear + 20.0);
    return TimelinePeriodItem(
      id: id,
      title: title,
      startYear: startYear,
      startDateLabel: startDateLabel,
      endYear: end,
      endDateLabel: endDateLabel ?? '${end.toInt()}',
      color: color,
      description: description,
      documentPath: documentPath,
    );
  }

  /// Converts this item into a point event.
  TimelineEventItem toPoint() => TimelineEventItem(
    id: id,
    title: title,
    startYear: startYear,
    startDateLabel: startDateLabel,
    color: color,
    description: description,
    documentPath: documentPath,
  );

  TimelineItem copyWith({
    String? id,
    String? title,
    double? startYear,
    String? startDateLabel,
    TimelineColor? color,
    String? description,
    String? documentPath,
    bool clearDocumentPath = false,
  });

  Map<String, Object?> toJson();

  /// The fields both kinds of item share, so the two [toJson] bodies do not
  /// drift apart. A null [documentPath] is left out rather than written as
  /// `null`: an absent link and a link to nothing are the same thing, and the
  /// file reads better without it.
  Map<String, Object?> _sharedJson(String type) => {
    'id': id,
    'type': type,
    'title': title,
    'start': startYear,
    'startLabel': startDateLabel,
    'color': color.id,
    if (description.isNotEmpty) 'description': description,
    if (isDocumentLink) 'document': documentPath,
  };

  static TimelineItem fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    if (id.isEmpty) {
      throw const TimelineFormatException('A timeline item has no id.');
    }
    final start = _number(json['start']);
    if (start == null) {
      throw TimelineFormatException(
        'Timeline item "$id" has no start year.',
      );
    }
    final startLabel = _string(json['startLabel'], fallback: '${start.toInt()}');
    final color = TimelineColor.fromId(json['color'] as String?);
    final description = _string(json['description']);
    final document = _string(json['document']);

    if (_string(json['type']) == 'period') {
      // A period whose end is missing or before its start is not a reason to
      // refuse the file — it is a hand-edit to be tidied into something the
      // track can draw.
      final end = _number(json['end']);
      final resolvedEnd = end == null || end < start ? start + 20 : end;
      return TimelinePeriodItem(
        id: id,
        title: _string(json['title']),
        startYear: start,
        startDateLabel: startLabel,
        endYear: resolvedEnd,
        endDateLabel: _string(
          json['endLabel'],
          fallback: '${resolvedEnd.toInt()}',
        ),
        color: color,
        description: description,
        documentPath: document.isEmpty ? null : document,
      );
    }

    return TimelineEventItem(
      id: id,
      title: _string(json['title']),
      startYear: start,
      startDateLabel: startLabel,
      color: color,
      description: description,
      documentPath: document.isEmpty ? null : document,
    );
  }
}

/// A point milestone occurring at a single moment.
class TimelineEventItem extends TimelineItem {
  const TimelineEventItem({
    required super.id,
    required super.title,
    required super.startYear,
    required super.startDateLabel,
    super.color = TimelineColor.fern,
    super.description,
    super.documentPath,
  });

  @override
  bool get isPeriod => false;

  @override
  Map<String, Object?> toJson() => _sharedJson('event');

  @override
  TimelineEventItem copyWith({
    String? id,
    String? title,
    double? startYear,
    String? startDateLabel,
    TimelineColor? color,
    String? description,
    String? documentPath,
    bool clearDocumentPath = false,
  }) => TimelineEventItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startYear: startYear ?? this.startYear,
    startDateLabel: startDateLabel ?? this.startDateLabel,
    color: color ?? this.color,
    description: description ?? this.description,
    documentPath: clearDocumentPath
        ? null
        : (documentPath ?? this.documentPath),
  );
}

/// A period spanning between a start and an end.
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
    super.documentPath,
  });

  final double endYear;
  final String endDateLabel;

  @override
  bool get isPeriod => true;

  @override
  Map<String, Object?> toJson() => {
    ..._sharedJson('period'),
    'end': endYear,
    'endLabel': endDateLabel,
  };

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
    String? documentPath,
    bool clearDocumentPath = false,
  }) => TimelinePeriodItem(
    id: id ?? this.id,
    title: title ?? this.title,
    startYear: startYear ?? this.startYear,
    startDateLabel: startDateLabel ?? this.startDateLabel,
    endYear: endYear ?? this.endYear,
    endDateLabel: endDateLabel ?? this.endDateLabel,
    color: color ?? this.color,
    description: description ?? this.description,
    documentPath: clearDocumentPath
        ? null
        : (documentPath ?? this.documentPath),
  );
}

/// One timeline, as stored in one `.unearth` file.
class Timeline {
  const Timeline({
    required this.id,
    required this.title,
    this.description = '',
    this.items = const [],
  });

  /// The `kind` this object is written under. A map, when there is one, is a
  /// different `kind` in the same container rather than a second extension.
  static const String kind = 'timeline';

  /// The schema this app writes. A file claiming a higher version is refused
  /// rather than opened and written back, because saving it would quietly
  /// strip whatever the newer version knew about and this one did not.
  static const int version = 1;

  /// Years used when a timeline has nothing in it yet, so the track still has
  /// a span to draw.
  static const double emptyMinYear = 1800;
  static const double emptyMaxYear = 1850;

  final String id;
  final String title;
  final String description;
  final List<TimelineItem> items;

  /// The earliest year among all items.
  double get minYear {
    if (items.isEmpty) return emptyMinYear;
    var min = items.first.startYear;
    for (final item in items) {
      if (item.startYear < min) min = item.startYear;
    }
    return min;
  }

  /// The latest year among all items, counting a period's end.
  double get maxYear {
    if (items.isEmpty) return emptyMaxYear;
    var max = items.first.startYear;
    for (final item in items) {
      final year = item is TimelinePeriodItem ? item.endYear : item.startYear;
      if (year > max) max = year;
    }
    return max;
  }

  TimelineItem? itemById(String? itemId) {
    if (itemId == null) return null;
    for (final item in items) {
      if (item.id == itemId) return item;
    }
    return null;
  }

  Timeline copyWith({
    String? id,
    String? title,
    String? description,
    List<TimelineItem>? items,
  }) => Timeline(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': version,
    'id': id,
    'title': title,
    'description': description,
    'items': [for (final item in items) item.toJson()],
  };

  static Timeline fromJson(Map<String, Object?> json) {
    final declaredKind = _string(json['kind']);
    if (declaredKind != kind) {
      throw TimelineFormatException(
        declaredKind.isEmpty
            ? 'That file does not say what kind of object it is.'
            : 'That file holds a "$declaredKind", not a timeline.',
      );
    }

    final declaredVersion = _number(json['version'])?.toInt() ?? version;
    if (declaredVersion > version) {
      throw TimelineFormatException(
        'That timeline was written by a newer version of DaySeven '
        '(format $declaredVersion). Update before opening it, so that saving '
        'it does not discard what this version cannot read.',
      );
    }

    final rawItems = json['items'];
    final items = <TimelineItem>[];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        items.add(TimelineItem.fromJson(Map<String, Object?>.from(raw)));
      }
    }
    // Sorted on the way in: the track draws left to right, and a hand-edited
    // file has no reason to have kept them in order.
    items.sort((a, b) => a.startYear.compareTo(b.startYear));

    return Timeline(
      id: _string(json['id'], fallback: 'timeline'),
      title: _string(json['title']),
      description: _string(json['description']),
      items: items,
    );
  }
}

/// Reads a year out of whatever the user typed into a date field.
///
/// Dates in an invented world are not dates: "Year 1803", "1803-13-20" with a
/// thirteenth month, "500 BCE" and plain "1803" all have to land somewhere on
/// the track. This turns any of them into the single number the track plots
/// against, and returns null only when there is no number in the text at all.
///
/// Carried over from the section parser that used to own it — the format it
/// read is gone, but a user typing "Year 1803" into the inspector is not.
double? parseYearLabel(String raw) {
  final text = raw.replaceAll('*', '').trim();
  if (text.isEmpty) return null;

  final isBce = RegExp(r'\b(bce|bc)\b', caseSensitive: false).hasMatch(text);
  double signed(double value) => isBce && value > 0 ? -value : value;

  // "Year 1803", optionally with a month and a day around it.
  final yearMatch = RegExp(
    r'Year\s+(-?\d+(?:\.\d+)?)',
    caseSensitive: false,
  ).firstMatch(text);
  if (yearMatch != null) {
    final year = double.tryParse(yearMatch.group(1)!);
    if (year != null) {
      var scalar = year;
      final monthMatch = RegExp(
        r'Month\s+(\d+)',
        caseSensitive: false,
      ).firstMatch(text);
      final dayMatch = RegExp(
        r'(\d+)\s+Month',
        caseSensitive: false,
      ).firstMatch(text);
      if (monthMatch != null) {
        final month = double.tryParse(monthMatch.group(1)!) ?? 1;
        // Clamped generously rather than to twelve: a world is allowed more
        // months than ours has.
        scalar += (month - 1).clamp(0, 20) / 12;
      }
      if (dayMatch != null) {
        final day = double.tryParse(dayMatch.group(1)!) ?? 1;
        scalar += day.clamp(0, 31) / 365;
      }
      return signed(scalar);
    }
  }

  // "1803", "1803-13-20", "1803/13/20".
  final isoMatch = RegExp(
    r'^(-?\d{1,6})(?:[-/](\d{1,2}))?(?:[-/](\d{1,2}))?',
  ).firstMatch(text);
  if (isoMatch != null) {
    final year = double.tryParse(isoMatch.group(1)!);
    if (year != null) {
      var scalar = year;
      final month = double.tryParse(isoMatch.group(2) ?? '');
      final day = double.tryParse(isoMatch.group(3) ?? '');
      if (month != null) scalar += (month - 1) / 12;
      if (day != null) scalar += day / 365;
      return signed(scalar);
    }
  }

  // Anything with a number in it at all.
  final numberMatch = RegExp(r'(-?\d+(?:\.\d+)?)').firstMatch(text);
  final number = numberMatch == null
      ? null
      : double.tryParse(numberMatch.group(1)!);
  return number == null ? null : signed(number);
}

String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

double? _number(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
