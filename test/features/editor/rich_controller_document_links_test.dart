import 'package:dayseven/features/editor/ui/rich_controller.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a page reference is one editable token and saves as a normal span', () {
    final controller = RichTextController(
      spans: const [
        TextSpanNode(text: 'See '),
        TextSpanNode(text: 'Aldenmoor', href: '../Places/Aldenmoor.md'),
        TextSpanNode(text: ' today.'),
      ],
    );

    expect(controller.text, 'See \uFFFC today.');
    expect(
      controller.toSpans()[1],
      const TextSpanNode(text: 'Aldenmoor', href: '../Places/Aldenmoor.md'),
    );

    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 5);
    controller.value = const TextEditingValue(
      text: 'See  today.',
      selection: TextSelection.collapsed(offset: 4),
    );
    expect(controller.toSpans().map((span) => span.text).join(), 'See  today.');
  });

  test('inserting a page reference replaces the selection', () {
    final controller = RichTextController(
      spans: const [TextSpanNode(text: 'See this page.')],
    );
    controller.selection = const TextSelection(baseOffset: 4, extentOffset: 13);

    controller.insertDocumentLink(
      label: 'Aldenmoor',
      href: 'Places/Aldenmoor.md',
    );

    expect(controller.text, 'See \uFFFC.');
    expect(controller.toSpans(), const [
      TextSpanNode(text: 'See '),
      TextSpanNode(text: 'Aldenmoor', href: 'Places/Aldenmoor.md'),
      TextSpanNode(text: '.'),
    ]);
  });

  testWidgets('renders the page icon and canonical name in sapphire', (
    tester,
  ) async {
    final controller = RichTextController(
      spans: const [
        TextSpanNode(text: 'Aldenmoor', href: 'Places/Aldenmoor.md'),
      ],
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        theme: dsTheme(),
        home: Scaffold(body: TextField(controller: controller)),
      ),
    );

    expect(find.byIcon(Icons.description_outlined), findsOneWidget);
    final label = tester.widget<Text>(find.text('Aldenmoor'));
    expect(label.style?.color, CF.sapphire);
  });

  testWidgets('Ctrl-click follows a page link on Windows', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      String? opened;
      final controller = RichTextController(
        spans: const [
          TextSpanNode(text: 'Aldenmoor', href: 'Places/Aldenmoor.md'),
        ],
        onOpenDocumentLink: (href) => opened = href,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: dsTheme(),
          home: Scaffold(body: TextField(controller: controller)),
        ),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(
        find.byKey(const ValueKey('document-link-Places/Aldenmoor.md')),
      );
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(opened, 'Places/Aldenmoor.md');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
