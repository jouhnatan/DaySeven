/// Domain action enum for application keybinds.
library;

import 'package:dayseven/app/workspace/editing_focus.dart';

/// Supported keybind actions across the application.
enum KeybindAction {
  bold,
  italic,
  underline,
  strikethrough;

  /// Human-readable label describing the action.
  String get label => switch (this) {
    KeybindAction.bold => 'Bold',
    KeybindAction.italic => 'Italics',
    KeybindAction.underline => 'Underline',
    KeybindAction.strikethrough => 'Strikethrough',
  };

  /// Convert from an [EditingFormat].
  static KeybindAction fromEditingFormat(EditingFormat format) => switch (format) {
    EditingFormat.bold => KeybindAction.bold,
    EditingFormat.italic => KeybindAction.italic,
    EditingFormat.underline => KeybindAction.underline,
    EditingFormat.strikethrough => KeybindAction.strikethrough,
  };

  /// Convert to [EditingFormat] if applicable.
  EditingFormat toEditingFormat() => switch (this) {
    KeybindAction.bold => EditingFormat.bold,
    KeybindAction.italic => EditingFormat.italic,
    KeybindAction.underline => EditingFormat.underline,
    KeybindAction.strikethrough => EditingFormat.strikethrough,
  };
}
