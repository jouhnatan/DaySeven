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
import 'package:dayseven/features/timeline/domain/timeline.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

const Uuid _uuid = Uuid();

/// The name a timeline is created under, before the user renames it.
const String kNewTimelineName = 'New timeline';

/// The seed a brand-new timeline is written with: one age and one event, so
/// the track has something to draw and the shape of the thing is visible
/// before anything has been typed.
Map<String, Object?> newTimelineSeed({String title = kNewTimelineName}) {
  final start = Timeline.emptyMinYear;
  return Timeline(
    id: _uuid.v7(),
    title: title,
    items: [
      TimelinePeriodItem(
        id: _uuid.v7(),
        title: 'New age',
        startYear: start,
        startDateLabel: '${start.toInt()}',
        endYear: start + 50,
        endDateLabel: '${(start + 50).toInt()}',
      ),
      TimelineEventItem(
        id: _uuid.v7(),
        title: 'New event',
        startYear: start + 25,
        startDateLabel: '${(start + 25).toInt()}',
      ),
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
    state = OpenTimeline(
      relativePath: relativePath,
      timeline: stored.title == fileName
          ? stored
          : stored.copyWith(title: fileName),
      dirty: false,
    );
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
  if (item == null || session == null || !item.isDocumentLink) return null;
  try {
    return await session.kb.readDocument(item.documentPath!);
  } on Object {
    // A link can outlive the document it points at. The pane says so; it does
    // not need an exception to do it.
    return null;
  }
});

/// Whether the reader pane is expanded over the map canvas.
final readerExpandedProvider = StateProvider<bool>((ref) => false);

/// Whether the timeline strip is expanded over the panes above it.
final stripExpandedProvider = StateProvider<bool>((ref) => false);

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
        : timeline.maxYear + 10;
    final startLabel = '${start.toInt()}';

    final TimelineItem item = isPeriod
        ? TimelinePeriodItem(
            id: _uuid.v7(),
            title: 'New age',
            startYear: start,
            startDateLabel: startLabel,
            endYear: start + 20,
            endDateLabel: '${(start + 20).toInt()}',
          )
        : TimelineEventItem(
            id: _uuid.v7(),
            title: 'New event',
            startYear: start,
            startDateLabel: startLabel,
          );

    _write(timeline.copyWith(items: [...timeline.items, item]));
    _ref.read(selectedTimelineItemIdProvider.notifier).state = item.id;
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
