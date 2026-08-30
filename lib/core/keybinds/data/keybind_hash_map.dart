/// Centralized hash map managing application keybinds.
library;

import 'dart:collection';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:dayseven/core/keybinds/domain/keybind.dart';
import 'package:dayseven/core/keybinds/domain/keybind_action.dart';

/// A dedicated hash map class for managing, querying, and describing keybinds.
class KeybindHashMap {
  KeybindHashMap([Map<KeybindAction, Keybind>? initialBindings])
      : _bindings = HashMap<KeybindAction, Keybind>.from(
          initialBindings ?? _defaultBindings,
        );

  final HashMap<KeybindAction, Keybind> _bindings;

  /// Default application keybinds.
  static final Map<KeybindAction, Keybind> _defaultBindings = {
    KeybindAction.bold: const Keybind(
      key: LogicalKeyboardKey.keyB,
      keyLabel: 'B',
    ),
    KeybindAction.italic: const Keybind(
      key: LogicalKeyboardKey.keyI,
      keyLabel: 'I',
    ),
    KeybindAction.underline: const Keybind(
      key: LogicalKeyboardKey.keyU,
      keyLabel: 'U',
    ),
    KeybindAction.strikethrough: const Keybind(
      key: LogicalKeyboardKey.keyX,
      keyLabel: 'X',
      shift: true,
    ),
  };

  /// Standard singleton instance for application-wide keybind reference.
  static final KeybindHashMap instance = KeybindHashMap();

  /// Retrieve keybind configuration for an action.
  Keybind? getKeybind(KeybindAction action) => _bindings[action];

  /// Retrieve keybind configuration using index operator.
  Keybind? operator [](KeybindAction action) => _bindings[action];

  /// Returns the platform-specific [SingleActivator] for an action.
  SingleActivator? getActivator(KeybindAction action, TargetPlatform platform) =>
      _bindings[action]?.activator(platform);

  /// Returns standard formatted shortcut text (e.g., "CMD + B" on macOS, "CTRL + B" on Windows).
  String getShortcutText(KeybindAction action, TargetPlatform platform) {
    final keybind = _bindings[action];
    if (keybind == null) return '';
    return keybind.formatShortcut(platform);
  }

  /// Returns full tooltip string (e.g., "Bold (CMD + B)").
  String getTooltipText(
    KeybindAction action,
    TargetPlatform platform, {
    String? customLabel,
  }) {
    final label = customLabel ?? action.label;
    final shortcut = getShortcutText(action, platform);
    return shortcut.isEmpty ? label : '$label ($shortcut)';
  }

  /// Returns all registered action entries.
  Iterable<MapEntry<KeybindAction, Keybind>> get entries => _bindings.entries;

  /// Returns all registered action keys.
  Iterable<KeybindAction> get keys => _bindings.keys;

  /// Returns all registered keybind configurations.
  Iterable<Keybind> get values => _bindings.values;

  /// Builds a map of [SingleActivator] to [KeybindAction] for Flutter's [Shortcuts] widget.
  Map<SingleActivator, KeybindAction> buildShortcutMap(TargetPlatform platform) {
    final result = <SingleActivator, KeybindAction>{};
    for (final entry in _bindings.entries) {
      result[entry.value.activator(platform)] = entry.key;
    }
    return result;
  }
}
