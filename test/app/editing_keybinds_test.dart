import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/workspace/editing_keybinds.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the keybind table contains only the four inline text modifiers', () {
    expect(kEditingKeybinds.keys, {
      EditingFormat.bold,
      EditingFormat.italic,
      EditingFormat.underline,
      EditingFormat.strikethrough,
    });
  });

  test('keybinds use Control on Windows and Command on macOS', () {
    for (final binding in kEditingKeybinds.values) {
      final windows = binding.activator(TargetPlatform.windows);
      expect(windows.control, isTrue);
      expect(windows.meta, isFalse);

      final macOS = binding.activator(TargetPlatform.macOS);
      expect(macOS.control, isFalse);
      expect(macOS.meta, isTrue);
    }

    expect(
      kEditingKeybinds[EditingFormat.bold]!.displayLabel(
        TargetPlatform.windows,
      ),
      'CTRL+B',
    );
    expect(
      kEditingKeybinds[EditingFormat.strikethrough]!.displayLabel(
        TargetPlatform.macOS,
      ),
      'COMMAND+SHIFT+X',
    );
  });

  test('editing focus compares active modifiers as an unordered set', () {
    EditingFocus focus(Set<EditingFormat> formats) => EditingFocus(
      blockId: 'paragraph',
      hasSelection: true,
      activeFormats: formats,
      align: BlockAlign.left,
      headingLevel: null,
    );

    final first = focus({EditingFormat.bold, EditingFormat.italic});
    final reordered = focus({EditingFormat.italic, EditingFormat.bold});

    expect(first, reordered);
    expect(first.hashCode, reordered.hashCode);
    expect(first.isActive(EditingFormat.bold), isTrue);
    expect(first.isActive(EditingFormat.underline), isFalse);
  });
}
