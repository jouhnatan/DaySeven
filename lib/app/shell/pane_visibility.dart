/// Visibility of optional panes in the application shell.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';

@immutable
class PaneVisibility {
  const PaneVisibility({
    this.knowledgeBase = true,
    this.timelineReader = true,
    this.timelineEditor = true,
    this.world = true,
  });

  /// The Knowledge Base tree, beside the Editor and Differences.
  final bool knowledgeBase;

  /// The reader, beside the Timelines workspace. A key of its own rather than
  /// a shared "side pane" flag: closing the tree while writing should not also
  /// close the reader the next time somebody opens a timeline.
  final bool timelineReader;

  /// The event and age editor, left of the map.
  final bool timelineEditor;

  /// The settings pane, left of the World workspace.
  final bool world;

  PaneVisibility copyWith({
    bool? knowledgeBase,
    bool? timelineReader,
    bool? timelineEditor,
    bool? world,
  }) => PaneVisibility(
    knowledgeBase: knowledgeBase ?? this.knowledgeBase,
    timelineReader: timelineReader ?? this.timelineReader,
    timelineEditor: timelineEditor ?? this.timelineEditor,
    world: world ?? this.world,
  );
}

class PaneVisibilityController extends StateNotifier<PaneVisibility> {
  PaneVisibilityController(this._ref) : super(const PaneVisibility()) {
    _restore();
  }

  final Ref _ref;
  static const _saveDelay = Duration(milliseconds: 400);
  static const _knowledgeBaseKey = 'knowledgeBase';
  static const _timelineReaderKey = 'timelineReader';
  static const _timelineEditorKey = 'timelineEditor';
  static const _worldKey = 'world';

  Timer? _saveDebounce;
  bool _changedLocally = false;

  Future<void> _restore() async {
    final store = await _ref.read(appStoreProvider.future);
    final saved = await store.paneVisibility();
    if (!mounted || _changedLocally) return;
    state = state.copyWith(
      knowledgeBase: saved[_knowledgeBaseKey] ?? state.knowledgeBase,
      timelineReader: saved[_timelineReaderKey] ?? state.timelineReader,
      timelineEditor: saved[_timelineEditorKey] ?? state.timelineEditor,
      world: saved[_worldKey] ?? state.world,
    );
  }

  void toggleKnowledgeBase() => setKnowledgeBaseVisible(!state.knowledgeBase);

  void setKnowledgeBaseVisible(bool visible) {
    if (state.knowledgeBase == visible) return;
    _set(state.copyWith(knowledgeBase: visible));
  }

  void toggleTimelineReader() =>
      setTimelineReaderVisible(!state.timelineReader);

  void setTimelineReaderVisible(bool visible) {
    if (state.timelineReader == visible) return;
    _set(state.copyWith(timelineReader: visible));
  }

  void toggleTimelineEditor() =>
      setTimelineEditorVisible(!state.timelineEditor);

  void setTimelineEditorVisible(bool visible) {
    if (state.timelineEditor == visible) return;
    _set(state.copyWith(timelineEditor: visible));
  }

  void toggleWorld() => setWorldVisible(!state.world);

  void setWorldVisible(bool visible) {
    if (state.world == visible) return;
    _set(state.copyWith(world: visible));
  }

  void _set(PaneVisibility next) {
    _changedLocally = true;
    state = next;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneVisibility(_knowledgeBaseKey, state.knowledgeBase);
      await store.setPaneVisibility(_timelineReaderKey, state.timelineReader);
      await store.setPaneVisibility(_timelineEditorKey, state.timelineEditor);
      await store.setPaneVisibility(_worldKey, state.world);
    });
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

final paneVisibilityProvider =
    StateNotifierProvider<PaneVisibilityController, PaneVisibility>(
      PaneVisibilityController.new,
    );
