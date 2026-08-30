/// Domain entity representing a keyboard shortcut configuration.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Represents a single keybind configuration.
@immutable
class Keybind {
  const Keybind({
    required this.key,
    required this.keyLabel,
    this.shift = false,
    this.alt = false,
  });

  final LogicalKeyboardKey key;
  final String keyLabel;
  final bool shift;
  final bool alt;

  /// Generates a platform-aware [SingleActivator].
  SingleActivator activator(TargetPlatform platform) => SingleActivator(
    key,
    meta: platform == TargetPlatform.macOS,
    control: platform != TargetPlatform.macOS,
    shift: shift,
    alt: alt,
  );

  /// Returns standard formatted shortcut text (e.g. 'CMD + B' or 'CTRL + B').
  String formatShortcut(TargetPlatform platform) {
    final modifier = platform == TargetPlatform.macOS ? 'CMD' : 'CTRL';
    final parts = [
      modifier,
      if (alt) 'ALT',
      if (shift) 'SHIFT',
      keyLabel,
    ];
    return parts.join(' + ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Keybind &&
          other.key == key &&
          other.keyLabel == keyLabel &&
          other.shift == shift &&
          other.alt == alt;

  @override
  int get hashCode => Object.hash(key, keyLabel, shift, alt);
}
