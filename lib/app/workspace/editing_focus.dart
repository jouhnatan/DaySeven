/// What the editor is currently pointed at, published for the shell.
///
/// The formatting toolbar lives in the bottom bar, which is a different subtree
/// from the editor: it cannot reach the editor's per-block controllers, and the
/// editor cannot reach down into the bar. This is the channel between them.
///
/// The state is a plain value object and the actions live on the controller,
/// deliberately. `StateNotifier` skips notifying when the new state `==` the
/// old one, so a value object with real equality is what stops every keystroke
/// from rebuilding the bottom bar; a closure held in the state would defeat it.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/blocks/blocks.dart';

/// The inline formats the toolbar can toggle.
enum EditingFormat { bold, italic, strikethrough, underline }

class EditingFocus {
  EditingFocus({
    required this.blockId,
    required this.hasSelection,
    required Set<EditingFormat> activeFormats,
    required this.align,
    required this.headingLevel,
  }) : activeFormats = Set.unmodifiable(activeFormats);

  final String blockId;

  /// Whether the current formatting state describes a selected range. At a
  /// collapsed caret, modifiers apply to text typed next instead.
  final bool hasSelection;

  /// Inline modifiers that are active throughout the selection or at the
  /// collapsed caret's typing position.
  final Set<EditingFormat> activeFormats;

  /// Block-level, so these stay available with no selection.
  final BlockAlign align;

  /// null when the focused block is body text.
  final int? headingLevel;

  bool isActive(EditingFormat format) => activeFormats.contains(format);

  @override
  bool operator ==(Object other) =>
      other is EditingFocus &&
      other.blockId == blockId &&
      other.hasSelection == hasSelection &&
      setEquals(other.activeFormats, activeFormats) &&
      other.align == align &&
      other.headingLevel == headingLevel;

  @override
  int get hashCode => Object.hash(
    blockId,
    hasSelection,
    Object.hashAllUnordered(activeFormats),
    align,
    headingLevel,
  );
}

/// The editor's side of the channel. Implemented by the editor screen.
abstract class EditingSurface {
  void toggleFormat(EditingFormat format);
  void setAlign(BlockAlign align);

  /// null turns the focused block back into body text.
  void setHeadingLevel(int? level);

  void insertImage();
}

class EditingFocusController extends StateNotifier<EditingFocus?> {
  EditingFocusController() : super(null);

  EditingSurface? _surface;

  void attach(EditingSurface surface) => _surface = surface;

  /// Identity-checked, so an editor being disposed after its replacement has
  /// already attached cannot clear the newcomer's surface.
  ///
  /// The `mounted` guards here and below are not ceremony: a test — or a
  /// closing window — can dispose the container before the widget tree
  /// unmounts, and the editor detaches from its own `dispose`.
  void detach(EditingSurface surface) {
    if (!identical(_surface, surface)) return;
    _surface = null;
    if (mounted) state = null;
  }

  void publish(EditingFocus focus) {
    if (mounted) state = focus;
  }

  void clear() {
    if (mounted) state = null;
  }

  void toggleFormat(EditingFormat format) => _surface?.toggleFormat(format);
  void setAlign(BlockAlign align) => _surface?.setAlign(align);
  void setHeadingLevel(int? level) => _surface?.setHeadingLevel(level);
  void insertImage() => _surface?.insertImage();
}

final editingFocusProvider =
    StateNotifierProvider<EditingFocusController, EditingFocus?>(
      (ref) => EditingFocusController(),
    );
