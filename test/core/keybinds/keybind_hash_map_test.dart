import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/core/keybinds/data/keybind_hash_map.dart';
import 'package:dayseven/core/keybinds/domain/keybind.dart';
import 'package:dayseven/core/keybinds/domain/keybind_action.dart';
import 'package:dayseven/core/keybinds/presentation/keybind_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KeybindAction', () {
    test('provides human-readable labels', () {
      expect(KeybindAction.bold.label, 'Bold');
      expect(KeybindAction.italic.label, 'Italics');
      expect(KeybindAction.underline.label, 'Underline');
      expect(KeybindAction.strikethrough.label, 'Strikethrough');
    });

    test('converts to and from EditingFormat correctly', () {
      for (final format in EditingFormat.values) {
        final action = KeybindAction.fromEditingFormat(format);
        expect(action.toEditingFormat(), format);
      }
    });
  });

  group('Keybind', () {
    test('activator uses Control on Windows and Command on macOS', () {
      const bold = Keybind(key: LogicalKeyboardKey.keyB, keyLabel: 'B');
      final winActivator = bold.activator(TargetPlatform.windows);
      expect(winActivator.control, isTrue);
      expect(winActivator.meta, isFalse);
      expect(winActivator.shift, isFalse);

      final macActivator = bold.activator(TargetPlatform.macOS);
      expect(macActivator.control, isFalse);
      expect(macActivator.meta, isTrue);
      expect(macActivator.shift, isFalse);

      const strikethrough = Keybind(
        key: LogicalKeyboardKey.keyX,
        keyLabel: 'X',
        shift: true,
      );
      final macShift = strikethrough.activator(TargetPlatform.macOS);
      expect(macShift.shift, isTrue);
      expect(macShift.meta, isTrue);
    });

    test('formatShortcut formats shortcuts according to platform conventions', () {
      const bold = Keybind(key: LogicalKeyboardKey.keyB, keyLabel: 'B');
      expect(bold.formatShortcut(TargetPlatform.macOS), 'CMD + B');
      expect(bold.formatShortcut(TargetPlatform.windows), 'CTRL + B');

      const strikethrough = Keybind(
        key: LogicalKeyboardKey.keyX,
        keyLabel: 'X',
        shift: true,
      );
      expect(
        strikethrough.formatShortcut(TargetPlatform.macOS),
        'CMD + SHIFT + X',
      );
      expect(
        strikethrough.formatShortcut(TargetPlatform.windows),
        'CTRL + SHIFT + X',
      );
    });

    test('equality and hashCode work as value object', () {
      const k1 = Keybind(key: LogicalKeyboardKey.keyB, keyLabel: 'B');
      const k2 = Keybind(key: LogicalKeyboardKey.keyB, keyLabel: 'B');
      const k3 = Keybind(
        key: LogicalKeyboardKey.keyB,
        keyLabel: 'B',
        shift: true,
      );

      expect(k1, equals(k2));
      expect(k1.hashCode, equals(k2.hashCode));
      expect(k1, isNot(equals(k3)));
    });
  });

  group('KeybindHashMap', () {
    test('contains all standard inline editing actions', () {
      final map = KeybindHashMap.instance;
      expect(map.keys, {
        KeybindAction.bold,
        KeybindAction.italic,
        KeybindAction.underline,
        KeybindAction.strikethrough,
      });
    });

    test('getKeybind and operator [] return the registered keybind', () {
      final map = KeybindHashMap.instance;
      expect(map.getKeybind(KeybindAction.bold)?.key, LogicalKeyboardKey.keyB);
      expect(map[KeybindAction.bold]?.key, LogicalKeyboardKey.keyB);
    });

    test('getShortcutText returns formatted string via function call', () {
      final map = KeybindHashMap.instance;
      expect(
        map.getShortcutText(KeybindAction.bold, TargetPlatform.macOS),
        'CMD + B',
      );
      expect(
        map.getShortcutText(KeybindAction.bold, TargetPlatform.windows),
        'CTRL + B',
      );
      expect(
        map.getShortcutText(KeybindAction.strikethrough, TargetPlatform.macOS),
        'CMD + SHIFT + X',
      );
    });

    test('getTooltipText formats action label and shortcut', () {
      final map = KeybindHashMap.instance;
      expect(
        map.getTooltipText(KeybindAction.bold, TargetPlatform.macOS),
        'Bold (CMD + B)',
      );
      expect(
        map.getTooltipText(KeybindAction.bold, TargetPlatform.windows),
        'Bold (CTRL + B)',
      );
      expect(
        map.getTooltipText(
          KeybindAction.bold,
          TargetPlatform.macOS,
          customLabel: 'Custom Bold',
        ),
        'Custom Bold (CMD + B)',
      );
    });

    test('buildShortcutMap maps SingleActivator to KeybindAction', () {
      final map = KeybindHashMap.instance;
      final macShortcuts = map.buildShortcutMap(TargetPlatform.macOS);
      expect(macShortcuts.length, 4);
      expect(macShortcuts.values, contains(KeybindAction.bold));

      final boldEntry = macShortcuts.entries.firstWhere(
        (e) => e.value == KeybindAction.bold,
      );
      expect(boldEntry.key.trigger, LogicalKeyboardKey.keyB);
      expect(boldEntry.key.meta, isTrue);
      expect(boldEntry.key.control, isFalse);
    });

    test('keybindHashMapProvider provides the standard instance', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(keybindHashMapProvider), KeybindHashMap.instance);
    });
  });
}
