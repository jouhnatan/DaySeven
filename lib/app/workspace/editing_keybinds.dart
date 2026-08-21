/// Platform-aware keyboard shortcuts for inline editor formatting.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';

/// Everything needed to bind and describe one inline-format shortcut.
class EditingKeybind {
  const EditingKeybind({
    required this.key,
    required this.keyLabel,
    this.shift = false,
  });

  final LogicalKeyboardKey key;
  final String keyLabel;
  final bool shift;

  /// Command is native on macOS; Control is native on Windows.
  SingleActivator activator(TargetPlatform platform) => SingleActivator(
    key,
    meta: platform == TargetPlatform.macOS,
    control: platform != TargetPlatform.macOS,
    shift: shift,
  );

  String displayLabel(TargetPlatform platform) => [
    platform == TargetPlatform.macOS ? 'COMMAND' : 'CTRL',
    if (shift) 'SHIFT',
    keyLabel,
  ].join('+');
}

/// The complete set of inline editor keybinds.
///
/// Keeping this as the single source of truth prevents the active shortcuts
/// and the toolbar tooltips from drifting apart.
const Map<EditingFormat, EditingKeybind> kEditingKeybinds = {
  EditingFormat.bold: EditingKeybind(
    key: LogicalKeyboardKey.keyB,
    keyLabel: 'B',
  ),
  EditingFormat.italic: EditingKeybind(
    key: LogicalKeyboardKey.keyI,
    keyLabel: 'I',
  ),
  EditingFormat.underline: EditingKeybind(
    key: LogicalKeyboardKey.keyU,
    keyLabel: 'U',
  ),
  EditingFormat.strikethrough: EditingKeybind(
    key: LogicalKeyboardKey.keyX,
    keyLabel: 'X',
    shift: true,
  ),
};
