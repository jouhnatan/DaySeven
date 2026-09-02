/// Visibility of optional panes in the application shell.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';

@immutable
class PaneVisibility {
  const PaneVisibility({this.knowledgeBase = true, this.timelineReader = true});

  /// The Knowledge Base tree, beside the Editor and Differences.
  final bool knowledgeBase;

  /// The reader, beside the Timelines workspace. A key of its own rather than
  /// a shared "side pane" flag: closing the tree while writing should not also
  /// close the reader the next time somebody opens a timeline.
  final bool timelineReader;

  PaneVisibility copyWith({bool? knowledgeBase, bool? timelineReader}) =>
      PaneVisibility(
        knowledgeBase: knowledgeBase ?? this.knowledgeBase,
        timelineReader: timelineReader ?? this.timelineReader,
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

  Timer? _saveDebounce;
  bool _changedLocally = false;

  Future<void> _restore() async {
    final store = await _ref.read(appStoreProvider.future);
    final saved = await store.paneVisibility();
    if (!mounted || _changedLocally) return;
    state = state.copyWith(
      knowledgeBase: saved[_knowledgeBaseKey] ?? state.knowledgeBase,
      timelineReader: saved[_timelineReaderKey] ?? state.timelineReader,
    );
  }

  void toggleKnowledgeBase() => setKnowledgeBaseVisible(!state.knowledgeBase);

  void setKnowledgeBaseVisible(bool visible) {
    if (state.knowledgeBase == visible) return;
    _set(state.copyWith(knowledgeBase: visible));
  }

  void toggleTimelineReader() => setTimelineReaderVisible(!state.timelineReader);

  void setTimelineReaderVisible(bool visible) {
    if (state.timelineReader == visible) return;
    _set(state.copyWith(timelineReader: visible));
  }

  void _set(PaneVisibility next) {
    _changedLocally = true;
    state = next;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneVisibility(_knowledgeBaseKey, state.knowledgeBase);
      await store.setPaneVisibility(_timelineReaderKey, state.timelineReader);
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
