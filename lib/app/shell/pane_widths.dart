/// The width of the shell's Knowledge Base pane.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';

/// How wide the Knowledge Base pane is. The workspace takes whatever is left,
/// so the pane is what the user drags. Persisted, so a window comes back the
/// way it was left.
class PaneWidths {
  const PaneWidths({this.panel = 248, this.reader = 320, this.editor = 268});

  /// The Knowledge Base pane, beside the Editor and Differences.
  final double panel;

  /// The reader pane, beside the Timelines workspace. Wider by default: it
  /// carries a document rather than a list of file names.
  final double reader;

  /// The event and age editor, left of the map in the Timelines view.
  final double editor;

  static const double minPanel = 180;
  static const double maxPanel = 560;

  /// The workspace never collapses to nothing, however far the handle is
  /// dragged.
  static const double minEditor = 320;

  PaneWidths copyWith({double? panel, double? reader, double? editor}) =>
      PaneWidths(
        panel: panel ?? this.panel,
        reader: reader ?? this.reader,
        editor: editor ?? this.editor,
      );
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
    state = PaneWidths(
      panel: widths['panel'] ?? state.panel,
      reader: widths['reader'] ?? state.reader,
      editor: widths['editor'] ?? state.editor,
    );
  }

  /// [available] is the width the workspace, the pane and the handle share, so
  /// a drag can be stopped before the workspace is squeezed out.
  void dragPanel(double delta, double available) {
    _set('panel', state.copyWith(panel: _clamp(state.panel - delta, available)));
  }

  /// [available] is the width the workspace, the reader and the handle share.
  void dragReader(double delta, double available) {
    _set(
      'reader',
      state.copyWith(reader: _clamp(state.reader - delta, available)),
    );
  }

  /// The editor is left of the workspace, so a drag to the right widens it —
  /// the opposite sign to the panes on the other side.
  void dragEditor(double delta, double available) {
    _set(
      'editor',
      state.copyWith(editor: _clamp(state.editor + delta, available)),
    );
  }

  /// Stops a drag before the workspace beside the pane is squeezed out.
  static double _clamp(double width, double available) {
    final headroom = available - PaneWidths.minEditor;
    return width.clamp(PaneWidths.minPanel, PaneWidths.maxPanel).clamp(
      PaneWidths.minPanel,
      headroom.clamp(PaneWidths.minPanel, PaneWidths.maxPanel),
    );
  }

  void _set(String key, PaneWidths widths) {
    state = widths;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneWidth(key, switch (key) {
        'panel' => state.panel,
        'editor' => state.editor,
        _ => state.reader,
      });
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
