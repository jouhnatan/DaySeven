import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every inline modifier uses the same selected-range toggle path', () {
    for (final format in EditingFormat.values) {
      final controller = RichTextController(
        spans: const [TextSpanNode(text: 'text')],
      );
      addTearDown(controller.dispose);
      const selection = TextSelection(baseOffset: 0, extentOffset: 4);

      expect(controller.isFormatActive(format, selection), isFalse);
      controller.toggleFormat(format, selection);
      expect(controller.isFormatActive(format, selection), isTrue);
      controller.toggleFormat(format, selection);
      expect(controller.isFormatActive(format, selection), isFalse);
    }
  });

  test('every inline modifier can toggle a collapsed typing format', () {
    for (final format in EditingFormat.values) {
      final controller = RichTextController(
        spans: const [TextSpanNode(text: 'text')],
      );
      addTearDown(controller.dispose);
      const selection = TextSelection.collapsed(offset: 0);

      controller.toggleFormat(format, selection);
      expect(controller.isFormatActive(format, selection), isTrue);

      controller.value = const TextEditingValue(
        text: 'Atext',
        selection: TextSelection.collapsed(offset: 1),
      );
      final inserted = controller.toSpans().first;
      expect(_isOn(format, inserted), isTrue);
    }
  });

  test('plain-text replacement uses the selection and typing format', () {
    final controller = RichTextController(
      spans: const [TextSpanNode(text: 'world', italic: true)],
    );
    addTearDown(controller.dispose);

    controller.replaceSelection(
      'Ω',
      selection: const TextSelection(baseOffset: 1, extentOffset: 4),
    );

    expect(controller.text, 'wΩd');
    expect(controller.selection, const TextSelection.collapsed(offset: 2));
    expect(controller.toSpans().single.italic, isTrue);
  });
}

bool _isOn(EditingFormat format, TextSpanNode value) => switch (format) {
  EditingFormat.bold => value.bold,
  EditingFormat.italic => value.italic,
  EditingFormat.strikethrough => value.strikethrough,
  EditingFormat.underline => value.underline,
};
