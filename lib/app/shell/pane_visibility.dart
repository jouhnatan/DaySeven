/// Visibility of optional panes in the application shell.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';

@immutable
class PaneVisibility {
  const PaneVisibility({this.knowledgeBase = true});

  final bool knowledgeBase;

  PaneVisibility copyWith({bool? knowledgeBase}) =>
      PaneVisibility(knowledgeBase: knowledgeBase ?? this.knowledgeBase);
}

class PaneVisibilityController extends StateNotifier<PaneVisibility> {
  PaneVisibilityController(this._ref) : super(const PaneVisibility()) {
    _restore();
  }

  final Ref _ref;
  static const _saveDelay = Duration(milliseconds: 400);
  static const _knowledgeBaseKey = 'knowledgeBase';

  Timer? _saveDebounce;
  bool _changedLocally = false;

  Future<void> _restore() async {
    final store = await _ref.read(appStoreProvider.future);
    final saved = await store.paneVisibility();
    if (!mounted || _changedLocally) return;
    state = state.copyWith(
      knowledgeBase: saved[_knowledgeBaseKey] ?? state.knowledgeBase,
    );
  }

  void toggleKnowledgeBase() => setKnowledgeBaseVisible(!state.knowledgeBase);

  void setKnowledgeBaseVisible(bool visible) {
    if (state.knowledgeBase == visible) return;
    _changedLocally = true;
    state = state.copyWith(knowledgeBase: visible);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneVisibility(_knowledgeBaseKey, state.knowledgeBase);
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
