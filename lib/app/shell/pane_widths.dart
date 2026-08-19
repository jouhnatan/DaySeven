/// The widths of the shell's two side panes.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';

/// How wide the two side panes are. The editor takes whatever is left, so the
/// panes are what the user drags. Persisted, so a window comes back the way it
/// was left.
class PaneWidths {
  const PaneWidths({this.rail = 140, this.panel = 248});

  final double rail;
  final double panel;

  static const double minRail = 104;
  static const double maxRail = 280;
  static const double minPanel = 180;
  static const double maxPanel = 560;

  /// The editor never collapses to nothing, however far a handle is dragged.
  static const double minEditor = 320;

  PaneWidths copyWith({double? rail, double? panel}) =>
      PaneWidths(rail: rail ?? this.rail, panel: panel ?? this.panel);
}

class PaneWidthsController extends StateNotifier<PaneWidths> {
  PaneWidthsController(this._ref) : super(const PaneWidths()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    final store = await _ref.read(appStoreProvider.future);
    final widths = await store.paneWidths();
    if (!mounted) return;
    state = PaneWidths(
      rail: widths['rail'] ?? state.rail,
      panel: widths['panel'] ?? state.panel,
    );
  }

  /// [available] is the width the three panes and their handles share, so a
  /// drag can be stopped before the editor is squeezed out.
  void dragRail(double delta, double available) {
    final headroom = available - state.panel - PaneWidths.minEditor;
    final rail = (state.rail + delta)
        .clamp(PaneWidths.minRail, PaneWidths.maxRail)
        .clamp(
          PaneWidths.minRail,
          headroom.clamp(PaneWidths.minRail, PaneWidths.maxRail),
        );
    _set(state.copyWith(rail: rail));
  }

  void dragPanel(double delta, double available) {
    final headroom = available - state.rail - PaneWidths.minEditor;
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
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneWidth('rail', state.rail);
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
