/// The width of the shell's Knowledge Base pane.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';

/// How wide the Knowledge Base pane is. The workspace takes whatever is left,
/// so the pane is what the user drags. Persisted, so a window comes back the
/// way it was left.
class PaneWidths {
  const PaneWidths({this.panel = 248});

  final double panel;

  static const double minPanel = 180;
  static const double maxPanel = 560;

  /// The workspace never collapses to nothing, however far the handle is
  /// dragged.
  static const double minEditor = 320;

  PaneWidths copyWith({double? panel}) =>
      PaneWidths(panel: panel ?? this.panel);
}

class PaneWidthsController extends StateNotifier<PaneWidths> {
  PaneWidthsController(this._ref) : super(const PaneWidths()) {
    _restore();
  }

  final Ref _ref;
  static const _saveDelay = Duration(milliseconds: 400);

  Future<void> _restore() async {
    final store = await _ref.read(appStoreProvider.future);
    final widths = await store.paneWidths();
    if (!mounted) return;
    state = PaneWidths(panel: widths['panel'] ?? state.panel);
  }

  /// [available] is the width the workspace, the pane and the handle share, so
  /// a drag can be stopped before the workspace is squeezed out.
  void dragPanel(double delta, double available) {
    final headroom = available - PaneWidths.minEditor;
    final panel = (state.panel - delta)
        .clamp(PaneWidths.minPanel, PaneWidths.maxPanel)
        .clamp(
          PaneWidths.minPanel,
          headroom.clamp(PaneWidths.minPanel, PaneWidths.maxPanel),
        );
    _set(state.copyWith(panel: panel));
  }

  void _set(PaneWidths widths) {
    state = widths;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneWidth('panel', state.panel);
    });
  }

  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

final paneWidthsProvider =
    StateNotifierProvider<PaneWidthsController, PaneWidths>(
      PaneWidthsController.new,
    );
