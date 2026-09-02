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

/// A nation, defined once on the timeline and referenced by the items it was
/// party to.
///
/// Held here rather than as free text on each item so that renaming a nation
/// is one edit rather than one per event, and rather than as a link to a
/// document so that a nation can be named before anybody has written it up.
class TimelineNation {
  const TimelineNation({
    required this.id,
    required this.name,
    this.color = TimelineColor.slate,
  });

  final String id;
  final String name;
  final TimelineColor color;

  TimelineNation copyWith({String? id, String? name, TimelineColor? color}) =>
      TimelineNation(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
      );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color.id,
  };

  static TimelineNation? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    if (id.isEmpty) return null;
    return TimelineNation(
      id: id,
      name: _string(json['name']),
      color: TimelineColor.fromId(json['color'] as String?),
    );
  }
}

/// An item on the timeline: either a point event or a period/span.
sealed class TimelineItem {
  const TimelineItem({
    required this.id,
    required this.title,
    required this.year,
    this.month,
    this.color = TimelineColor.fern,
    this.description = '',
    this.mainDocumentPath,
    this.documentPaths = const [],
    this.nationIds = const [],
  });

  final String id;
  final String title;

  /// The year this happens in. Whole years; a world's own calendar decides
  /// what a year means.
  final int year;

  /// The month within [year], or null for something dated only to the year.
  ///
  /// Deliberately unbounded: a world is allowed a thirteenth month, and the
  /// timeline's own [Timeline.monthsPerYear] says how many it has.
  final int? month;

  final TimelineColor color;

  /// Used on the right when there is no [mainDocumentPath] to read instead.
  final String description;

  /// The document this item is really about: what the reader shows, and what
  /// it takes its heading from.
  final String? mainDocumentPath;

  /// Every other document this item connects to, in the order they were added.
  /// Does not repeat [mainDocumentPath].
  final List<String> documentPaths;

  /// The nations party to this, by [TimelineNation.id].
  final List<String> nationIds;

  bool get isPeriod;

  bool get hasMainDocument =>
      mainDocumentPath != null && mainDocumentPath!.trim().isNotEmpty;

  /// Every document this item touches, the main one first.
  List<String> get allDocumentPaths => [
    if (hasMainDocument) mainDocumentPath!,
    ...documentPaths,
  ];

  /// Converts this item into a period stretching over time.
  TimelinePeriodItem toPeriod({int? endYear, int? endMonth}) =>
      TimelinePeriodItem(
        id: id,
        title: title,
        year: year,
        month: month,
        endYear: endYear ?? (year + 20),
        endMonth: endMonth,
        color: color,
        description: description,
        mainDocumentPath: mainDocumentPath,
        documentPaths: documentPaths,
        nationIds: nationIds,
      );

  /// Converts this item into a point event.
  TimelineEventItem toPoint() => TimelineEventItem(
    id: id,
    title: title,
    year: year,
    month: month,
    color: color,
    description: description,
    mainDocumentPath: mainDocumentPath,
    documentPaths: documentPaths,
    nationIds: nationIds,
  );

  TimelineItem copyWith({
    String? id,
    String? title,
    int? year,
    int? month,
    bool clearMonth = false,
    TimelineColor? color,
    String? description,
    String? mainDocumentPath,
    bool clearMainDocumentPath = false,
    List<String>? documentPaths,
    List<String>? nationIds,
  });

  Map<String, Object?> toJson();

  /// The fields both kinds of item share, so the two [toJson] bodies do not
  /// drift apart. Empty values are left out rather than written as null: the
  /// file reads better without them, and an absent link and a link to nothing
  /// are the same thing.
  Map<String, Object?> _sharedJson(String type) => {
    'id': id,
    'type': type,
    'title': title,
    'year': year,
    if (month != null) 'month': month,
    'color': color.id,
    if (description.isNotEmpty) 'description': description,
    if (hasMainDocument) 'document': mainDocumentPath,
    if (documentPaths.isNotEmpty) 'documents': documentPaths,
    if (nationIds.isNotEmpty) 'nations': nationIds,
  };

  static TimelineItem fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    if (id.isEmpty) {
      throw const TimelineFormatException('A timeline item has no id.');
    }

    // `start` is how version 1 wrote the date, as one scalar. Read as the year
    // it fell in; the month it never recorded stays absent.
    final year = _int(json['year']) ?? _number(json['start'])?.floor();
    if (year == null) {
      throw TimelineFormatException('Timeline item "$id" has no year.');
    }

    final main = _string(json['document']);
    final others = _stringList(json['documents'])
      ..removeWhere((path) => path == main);

    final shared = (
      title: _string(json['title']),
      year: year,
      month: _positiveInt(json['month']),
      color: TimelineColor.fromId(json['color'] as String?),
      description: _string(json['description']),
      mainDocumentPath: main.isEmpty ? null : main,
      documentPaths: others,
      nationIds: _stringList(json['nations']),
    );

    if (_string(json['type']) == 'period') {
      final rawEnd = _int(json['end']) ?? _number(json['end'])?.floor();
      // A period whose end is missing or before its start is not a reason to
      // refuse the file — it is a hand-edit to be tidied into something the
      // track can draw.
      final end = rawEnd == null || rawEnd < year ? year + 20 : rawEnd;
      return TimelinePeriodItem(
        id: id,
        title: shared.title,
        year: shared.year,
        month: shared.month,
        endYear: end,
        endMonth: _positiveInt(json['endMonth']),
        color: shared.color,
        description: shared.description,
        mainDocumentPath: shared.mainDocumentPath,
        documentPaths: shared.documentPaths,
        nationIds: shared.nationIds,
      );
    }

    return TimelineEventItem(
      id: id,
      title: shared.title,
      year: shared.year,
      month: shared.month,
      color: shared.color,
      description: shared.description,
      mainDocumentPath: shared.mainDocumentPath,
      documentPaths: shared.documentPaths,
      nationIds: shared.nationIds,
    );
  }
}

/// A point milestone occurring at a single moment.
class TimelineEventItem extends TimelineItem {
  const TimelineEventItem({
    required super.id,
    required super.title,
    required super.year,
    super.month,
    super.color = TimelineColor.fern,
    super.description,
    super.mainDocumentPath,
    super.documentPaths,
    super.nationIds,
  });

  @override
  bool get isPeriod => false;

  @override
  Map<String, Object?> toJson() => _sharedJson('event');

  @override
  TimelineEventItem copyWith({
    String? id,
    String? title,
    int? year,
    int? month,
    bool clearMonth = false,
    TimelineColor? color,
    String? description,
    String? mainDocumentPath,
    bool clearMainDocumentPath = false,
    List<String>? documentPaths,
    List<String>? nationIds,
  }) => TimelineEventItem(
    id: id ?? this.id,
    title: title ?? this.title,
    year: year ?? this.year,
    month: clearMonth ? null : (month ?? this.month),
    color: color ?? this.color,
    description: description ?? this.description,
    mainDocumentPath: clearMainDocumentPath
        ? null
        : (mainDocumentPath ?? this.mainDocumentPath),
    documentPaths: documentPaths ?? this.documentPaths,
    nationIds: nationIds ?? this.nationIds,
  );
}

/// An age: a span between a start and an end.
class TimelinePeriodItem extends TimelineItem {
  const TimelinePeriodItem({
    required super.id,
    required super.title,
    required super.year,
    required this.endYear,
    super.month,
    this.endMonth,
    super.color = TimelineColor.fern,
    super.description,
    super.mainDocumentPath,
    super.documentPaths,
    super.nationIds,
  });

  final int endYear;
  final int? endMonth;

  @override
  bool get isPeriod => true;

  @override
  Map<String, Object?> toJson() => {
    ..._sharedJson('period'),
    'end': endYear,
    if (endMonth != null) 'endMonth': endMonth,
  };

  @override
  TimelinePeriodItem copyWith({
    String? id,
    String? title,
    int? year,
    int? month,
    bool clearMonth = false,
    int? endYear,
    int? endMonth,
    bool clearEndMonth = false,
    TimelineColor? color,
    String? description,
    String? mainDocumentPath,
    bool clearMainDocumentPath = false,
    List<String>? documentPaths,
    List<String>? nationIds,
  }) => TimelinePeriodItem(
    id: id ?? this.id,
    title: title ?? this.title,
    year: year ?? this.year,
    month: clearMonth ? null : (month ?? this.month),
    endYear: endYear ?? this.endYear,
    endMonth: clearEndMonth ? null : (endMonth ?? this.endMonth),
    color: color ?? this.color,
    description: description ?? this.description,
    mainDocumentPath: clearMainDocumentPath
        ? null
        : (mainDocumentPath ?? this.mainDocumentPath),
    documentPaths: documentPaths ?? this.documentPaths,
    nationIds: nationIds ?? this.nationIds,
  );
}

/// One timeline, as stored in one `.unearth` file.
class Timeline {
  const Timeline({
    required this.id,
    required this.title,
    this.description = '',
    this.monthsPerYear = defaultMonthsPerYear,
    this.nations = const [],
    this.items = const [],
  });

  /// The `kind` this object is written under. A map, when there is one, is a
  /// different `kind` in the same container rather than a second extension.
  static const String kind = 'timeline';

  /// The schema this app writes.
  ///
  /// Version 1 dated an item with one scalar, `start`, and knew nothing about
  /// nations or about a document being the main one. Version 2 is read and
  /// written here; a version 1 file is upgraded on the way in.
  static const int version = 2;

  /// Years used when a timeline has nothing in it yet, so the track still has
  /// a span to draw.
  static const int emptyMinYear = 1800;
  static const int emptyMaxYear = 1850;

  /// How many months a year has here, when nobody has said otherwise.
  static const int defaultMonthsPerYear = 12;

  final String id;
  final String title;
  final String description;

  /// How many months this world's year has. Only ever used to place a dated
  /// item between one year mark and the next, so a thirteen-month calendar
  /// lands where its owner expects rather than spilling into the year after.
  final int monthsPerYear;

  final List<TimelineNation> nations;
  final List<TimelineItem> items;

  /// Where [item] sits on the track.
  double plotStart(TimelineItem item) => _plot(item.year, item.month);

  /// Where [item] stops. The same as [plotStart] for anything but an age.
  double plotEnd(TimelineItem item) => switch (item) {
    final TimelinePeriodItem p => _plot(p.endYear, p.endMonth),
    _ => plotStart(item),
  };

  double _plot(int year, int? month) {
    if (month == null) return year.toDouble();
    final months = monthsPerYear < 1 ? defaultMonthsPerYear : monthsPerYear;
    return year + ((month - 1).clamp(0, months - 1) / months);
  }

  /// How [item]'s date reads. Months have no names here — a world may have any
  /// number of them — so a month is said as a number.
  String dateLabel(TimelineItem item) => switch (item) {
    final TimelinePeriodItem p =>
      '${_label(p.year, p.month)} → ${_label(p.endYear, p.endMonth)}',
    _ => _label(item.year, item.month),
  };

  static String _label(int year, int? month) =>
      month == null ? '$year' : 'Month $month, $year';

  TimelineNation? nationById(String id) {
    for (final nation in nations) {
      if (nation.id == id) return nation;
    }
    return null;
  }

  /// The nations party to [item], in the order the timeline lists them, so two
  /// items never show the same pair in a different order.
  List<TimelineNation> nationsOf(TimelineItem item) => [
    for (final nation in nations)
      if (item.nationIds.contains(nation.id)) nation,
  ];

  /// The earliest point among all items.
  double get minYear {
    if (items.isEmpty) return emptyMinYear.toDouble();
    var min = plotStart(items.first);
    for (final item in items) {
      final start = plotStart(item);
      if (start < min) min = start;
    }
    return min;
  }

  /// The latest point among all items, counting where an age ends.
  double get maxYear {
    if (items.isEmpty) return emptyMaxYear.toDouble();
    var max = plotEnd(items.first);
    for (final item in items) {
      final end = plotEnd(item);
      if (end > max) max = end;
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
    int? monthsPerYear,
    List<TimelineNation>? nations,
    List<TimelineItem>? items,
  }) => Timeline(
    id: id ?? this.id,
    title: title ?? this.title,
    description: description ?? this.description,
    monthsPerYear: monthsPerYear ?? this.monthsPerYear,
    nations: nations ?? this.nations,
    items: items ?? this.items,
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': version,
    'id': id,
    'title': title,
    'description': description,
    'monthsPerYear': monthsPerYear,
    'nations': [for (final nation in nations) nation.toJson()],
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

    final declaredVersion = _int(json['version']) ?? version;
    if (declaredVersion > version) {
      throw TimelineFormatException(
        'That timeline was written by a newer version of DaySeven '
        '(format $declaredVersion). Update before opening it, so that saving '
        'it does not discard what this version cannot read.',
      );
    }

    final nations = <TimelineNation>[];
    final rawNations = json['nations'];
    if (rawNations is List) {
      for (final raw in rawNations) {
        if (raw is! Map) continue;
        final nation = TimelineNation.fromJson(Map<String, Object?>.from(raw));
        if (nation != null) nations.add(nation);
      }
    }

    final items = <TimelineItem>[];
    final rawItems = json['items'];
    if (rawItems is List) {
      for (final raw in rawItems) {
        if (raw is! Map) continue;
        items.add(TimelineItem.fromJson(Map<String, Object?>.from(raw)));
      }
    }

    final known = {for (final nation in nations) nation.id};
    final timeline = Timeline(
      id: _string(json['id'], fallback: 'timeline'),
      title: _string(json['title']),
      description: _string(json['description']),
      monthsPerYear:
          _positiveInt(json['monthsPerYear']) ?? defaultMonthsPerYear,
      nations: nations,
      items: [
        // A reference to a nation the file does not define is dropped rather
        // than kept as an id nothing can render.
        for (final item in items)
          item.nationIds.every(known.contains)
              ? item
              : item.copyWith(
                  nationIds: [
                    for (final id in item.nationIds)
                      if (known.contains(id)) id,
                  ],
                ),
      ],
    );

    // Sorted on the way out: the track draws left to right, and a hand-edited
    // file has no reason to have kept them in order.
    final sorted = [...timeline.items]
      ..sort(
        (a, b) => timeline.plotStart(a).compareTo(timeline.plotStart(b)),
      );
    return timeline.copyWith(items: sorted);
  }
}

String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

List<String> _stringList(Object? value) => switch (value) {
  final List<Object?> list => [
    for (final entry in list)
      if (entry is String && entry.trim().isNotEmpty) entry,
  ],
  _ => <String>[],
};

int? _int(Object? value) => switch (value) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

/// A month, or a month count, is only meaningful above zero.
int? _positiveInt(Object? value) {
  final parsed = _int(value);
  return parsed == null || parsed < 1 ? null : parsed;
}

double? _number(Object? value) => switch (value) {
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};
