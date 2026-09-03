/// The timeline currently open: its contents, whether it has unsaved changes,
/// and the debounced save that follows an edit.
///
/// This mirrors `DocumentController` deliberately. A timeline is now a file
/// like a document is a file, and the open-edit-debounce-save shape it needs
/// is the one the editor already uses.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/timelines/domain/timeline.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/theme.dart';

const Uuid _uuid = Uuid();

/// The name a timeline is created under, before the user renames it.
const String kNewTimelineName = 'New timeline';

/// The seed a brand-new timeline is written with: one age and one event, so
/// the track has something to draw and the shape of the thing is visible
/// before anything has been typed.
Map<String, Object?> newTimelineSeed({String title = kNewTimelineName}) {
  const start = Timeline.emptyMinYear;
  return Timeline(
    id: _uuid.v7(),
    title: title,
    items: [
      TimelinePeriodItem(
        id: _uuid.v7(),
        title: 'New age',
        year: start,
        endYear: start + 50,
      ),
      TimelineEventItem(id: _uuid.v7(), title: 'New event', year: start + 25),
    ],
  ).toJson();
}

class OpenTimeline {
  const OpenTimeline({
    required this.relativePath,
    required this.timeline,
    required this.dirty,
  });

  final String relativePath;
  final Timeline timeline;

  /// True between an edit and the debounced save that follows it.
  final bool dirty;

  OpenTimeline copyWith({
    String? relativePath,
    Timeline? timeline,
    bool? dirty,
  }) => OpenTimeline(
    relativePath: relativePath ?? this.relativePath,
    timeline: timeline ?? this.timeline,
    dirty: dirty ?? this.dirty,
  );
}

class TimelineController extends StateNotifier<OpenTimeline?> {
  TimelineController(this._ref) : super(null);

  final Ref _ref;
  Timer? _saveDebounce;
  int _openGeneration = 0;
  static const _saveDelay = Duration(milliseconds: 600);

  Future<void> open(String relativePath) async {
    final generation = ++_openGeneration;
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;

    await flush();
    if (!mounted || generation != _openGeneration) return;
    final json = await session.kb.readObjectJson(relativePath);
    if (!mounted || generation != _openGeneration) return;

    final stored = Timeline.fromJson(json);
    // The file name is the name: the same rule documents follow, so renaming
    // in the tree renames the thing rather than leaving two names to reconcile.
    final fileName = objectNameFromPath(relativePath);
    final timeline = stored.title == fileName
        ? stored
        : stored.copyWith(title: fileName);
    state = OpenTimeline(
      relativePath: relativePath,
      timeline: timeline,
      dirty: false,
    );

    // Choosing a timeline is already a choice of what to work on, so the
    // earliest thing on it is selected here rather than making the person
    // click again on the track before the editor has anything to show.
    _ref.read(selectedTimelineItemIdProvider.notifier).state = timeline
        .items
        .firstOrNull
        ?.id;
  }

  void close({bool save = true}) {
    _openGeneration++;
    if (save) {
      unawaited(flush());
    } else {
      _saveDebounce?.cancel();
    }
    state = null;
  }

  /// Applies an edit and schedules a save, debounced so that dragging an item
  /// along the track does not write the file on every frame.
  void edit(Timeline timeline) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(timeline: timeline, dirty: true);

    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () {
      unawaited(flush());
    });
  }

  /// Updates the open path without reloading, after a rename or a move.
  void relocate(String fromPath, String toPath, {String? title}) {
    final current = state;
    if (current == null || current.relativePath != fromPath) return;
    state = current.copyWith(
      relativePath: toPath,
      timeline: title == null
          ? current.timeline
          : current.timeline.copyWith(title: title),
    );
  }

  /// Forgets the open timeline when the file behind it is gone.
  void closeIfOpen(String relativePath) {
    final current = state;
    if (current == null) return;
    if (current.relativePath != relativePath &&
        !current.relativePath.startsWith('$relativePath/')) {
      return;
    }
    _saveDebounce?.cancel();
    _openGeneration++;
    state = null;
  }

  /// Writes the open timeline to disk.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    final current = state;
    final session = _ref.read(kbSessionProvider);
    if (current == null || session == null || !current.dirty) return;

    await session.kb.writeObjectJson(
      current.relativePath,
      current.timeline.toJson(),
    );
    // An edit may have arrived while the disk write was in flight. Only the
    // exact snapshot that was written becomes clean.
    if (mounted && identical(state, current)) {
      state = current.copyWith(dirty: false);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

final openTimelineProvider =
    StateNotifierProvider<TimelineController, OpenTimeline?>(
      TimelineController.new,
    );

/// The timeline objects in the open Knowledge Base.
///
/// Re-read whenever the session's tree changes, which is what `refreshTree`
/// already bumps after a create, rename, move or delete.
final timelineObjectsProvider = FutureProvider<List<KbFile>>((ref) async {
  final session = ref.watch(kbSessionProvider);
  if (session == null) return const [];
  final objects = await session.kb.readObjects();
  return objects;
});

/// The item selected on the track, by id.
final selectedTimelineItemIdProvider = StateProvider<String?>((ref) => null);

/// The selected item itself, if it is still in the open timeline.
final selectedTimelineItemProvider = Provider<TimelineItem?>((ref) {
  final open = ref.watch(openTimelineProvider);
  final selectedId = ref.watch(selectedTimelineItemIdProvider);
  return open?.timeline.itemById(selectedId);
});

/// The document the selected item points at, loaded for reading only.
///
/// Deliberately not routed through `documentControllerProvider`: selecting an
/// event here must not change what the Editor view has open, or clicking
/// around a timeline would silently move somebody's editing session.
final timelineReaderDocumentProvider = FutureProvider<BlockDocument?>((
  ref,
) async {
  final item = ref.watch(selectedTimelineItemProvider);
  final session = ref.watch(kbSessionProvider);
  if (item == null || session == null || !item.hasMainDocument) return null;
  try {
    return await session.kb.readDocument(item.mainDocumentPath!);
  } on Object {
    // A link can outlive the document it points at. The pane says so; it does
    // not need an exception to do it.
    return null;
  }
});

/// Mutating actions on the open timeline.
final timelineActionControllerProvider = Provider<TimelineActionController>((
  ref,
) {
  return TimelineActionController(ref);
});

class TimelineActionController {
  TimelineActionController(this._ref);

  final Ref _ref;

  Timeline? get _timeline => _ref.read(openTimelineProvider)?.timeline;

  void _write(Timeline next) =>
      _ref.read(openTimelineProvider.notifier).edit(next);

  /// Adds a new event or age after everything already on the track.
  void addItem({required bool isPeriod}) {
    final timeline = _timeline;
    if (timeline == null) return;

    final start = timeline.items.isEmpty
        ? Timeline.emptyMinYear
        : timeline.maxYear.ceil() + 10;

    final TimelineItem item = isPeriod
        ? TimelinePeriodItem(
            id: _uuid.v7(),
            title: 'New age',
            year: start,
            endYear: start + 20,
          )
        : TimelineEventItem(id: _uuid.v7(), title: 'New event', year: start);

    _write(timeline.copyWith(items: [...timeline.items, item]));
    _ref.read(selectedTimelineItemIdProvider.notifier).state = item.id;
  }

  /// Defines a nation on the timeline and returns it, so the caller can put it
  /// straight onto the item that prompted it.
  TimelineNation? addNation(String name) {
    final timeline = _timeline;
    if (timeline == null) return null;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return null;

    // The same nation named twice is one nation. Matched case-insensitively,
    // because "the Vale" and "The Vale" are not two powers.
    for (final existing in timeline.nations) {
      if (existing.name.toLowerCase() == trimmed.toLowerCase()) return existing;
    }

    final nation = TimelineNation(
      id: _uuid.v7(),
      name: trimmed,
      // Cycled so a new nation is not born the same colour as the last one.
      color: TimelineColor
          .values[timeline.nations.length % TimelineColor.values.length],
    );
    _write(timeline.copyWith(nations: [...timeline.nations, nation]));
    return nation;
  }

  void updateNation(TimelineNation updated) {
    final timeline = _timeline;
    if (timeline == null) return;
    _write(
      timeline.copyWith(
        nations: [
          for (final nation in timeline.nations)
            if (nation.id == updated.id) updated else nation,
        ],
      ),
    );
  }

  /// Removes a nation from the timeline, and from every item party to it — an
  /// id no nation answers to would render as nothing at all.
  void removeNation(String nationId) {
    final timeline = _timeline;
    if (timeline == null) return;
    _write(
      timeline.copyWith(
        nations: [
          for (final nation in timeline.nations)
            if (nation.id != nationId) nation,
        ],
        items: [
          for (final item in timeline.items)
            if (item.nationIds.contains(nationId))
              item.copyWith(
                nationIds: [
                  for (final id in item.nationIds)
                    if (id != nationId) id,
                ],
              )
            else
              item,
        ],
      ),
    );
  }

  /// Adds or removes a nation on one item.
  void toggleNationOnItem(TimelineItem item, String nationId) {
    final has = item.nationIds.contains(nationId);
    updateItem(
      item.copyWith(
        nationIds: has
            ? [
                for (final id in item.nationIds)
                  if (id != nationId) id,
              ]
            : [...item.nationIds, nationId],
      ),
    );
  }

  /// Connects a document to an item. The first one connected becomes the main
  /// document, because an item with exactly one document and no main one would
  /// otherwise show nothing on the right.
  void linkDocument(TimelineItem item, String path) {
    if (path.trim().isEmpty) return;
    if (item.allDocumentPaths.contains(path)) return;
    updateItem(
      item.hasMainDocument
          ? item.copyWith(documentPaths: [...item.documentPaths, path])
          : item.copyWith(mainDocumentPath: path),
    );
  }

  void unlinkDocument(TimelineItem item, String path) {
    if (item.mainDocumentPath == path) {
      // Something else steps up rather than the item losing its reader.
      final remaining = [...item.documentPaths];
      final promoted = remaining.isEmpty ? null : remaining.removeAt(0);
      updateItem(
        promoted == null
            ? item.copyWith(clearMainDocumentPath: true, documentPaths: const [])
            : item.copyWith(
                mainDocumentPath: promoted,
                documentPaths: remaining,
              ),
      );
      return;
    }
    updateItem(
      item.copyWith(
        documentPaths: [
          for (final other in item.documentPaths)
            if (other != path) other,
        ],
      ),
    );
  }

  /// Makes one of an item's documents the one the reader shows.
  void makeMainDocument(TimelineItem item, String path) {
    if (item.mainDocumentPath == path) return;
    final others = [
      for (final other in item.allDocumentPaths)
        if (other != path) other,
    ];
    updateItem(item.copyWith(mainDocumentPath: path, documentPaths: others));
  }

  void updateItem(TimelineItem updated) {
    final timeline = _timeline;
    if (timeline == null) return;
    _write(
      timeline.copyWith(
        items: [
          for (final item in timeline.items)
            if (item.id == updated.id) updated else item,
        ],
      ),
    );
  }

  void removeItem(String itemId) {
    final timeline = _timeline;
    if (timeline == null) return;
    final remaining = [
      for (final item in timeline.items)
        if (item.id != itemId) item,
    ];
    _write(timeline.copyWith(items: remaining));

    if (_ref.read(selectedTimelineItemIdProvider) == itemId) {
      _ref.read(selectedTimelineItemIdProvider.notifier).state = remaining
          .isNotEmpty
          ? remaining.first.id
          : null;
    }
  }

  void updateDescription(String description) {
    final timeline = _timeline;
    if (timeline == null) return;
    _write(timeline.copyWith(description: description));
  }

  /// Selects an item on the track, or deselects when null.
  void selectItem(String? itemId) {
    _ref.read(selectedTimelineItemIdProvider.notifier).state = itemId;
  }
}
