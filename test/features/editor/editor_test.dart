import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';
import 'package:dayseven/shared/ui/block_text_style.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Renders the editor over a real Knowledge Base in a temporary folder, so the
/// save path exercises actual files.
///
/// All of the setup touches the disk and SQLite, so it runs inside
/// [WidgetTester.runAsync]: real I/O futures never complete in the fake-async
/// zone a widget test otherwise runs in.
Future<(ProviderContainer, KnowledgeBase, String)> openEditor(
  WidgetTester tester,
  Directory temp, {
  BlockDocument? seed,
  Brightness brightness = Brightness.dark,
}) async {
  final container = ProviderContainer();
  addTearDown(container.dispose);

  late KnowledgeBase kb;
  late String path;

  await tester.runAsync(() async {
    await container
        .read(kbControllerProvider.notifier)
        .openFolder(temp.path, createWithName: 'MyWorld');
    final session = container.read(kbSessionProvider)!;
    kb = session.kb;

    path = await kb.createDocument(title: 'Aldenmoor');
    if (seed != null) {
      await kb.writeDocument(path, seed);
    }
    final document = await kb.readDocument(path);
    session.index.upsert(path, document);
    await container.read(kbControllerProvider.notifier).refreshTree();
    await container.read(documentControllerProvider.notifier).open(path);
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: dsTheme(brightness),
        home: const Scaffold(body: EditorScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();

  return (container, kb, path);
}

BlockDocument seedWith(String text) => BlockDocument(
  id: 'doc-1',
  title: 'Aldenmoor',
  blocks: [
    ParagraphBlock(
      id: 'b1',
      spans: [TextSpanNode(text: text)],
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_editor_test');
    support = await Directory.systemTemp.createTemp('dayseven_support');

    // The app keeps its recent-files list in the application support directory,
    // which has no platform implementation under `flutter test`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await support.exists()) await support.delete(recursive: true);
  });

  testWidgets('typing lands in the document and is saved to the file', (
    tester,
  ) async {
    final (container, kb, path) = await openEditor(tester, temp);

    await tester.enterText(
      find.byType(TextField).last,
      'Fog sits low over the fen.',
    );
    await tester.pump();

    late BlockDocument onDisk;
    await tester.runAsync(() async {
      await container.read(documentControllerProvider.notifier).flush();
      onDisk = await kb.readDocument(path);
    });

    expect(onDisk.plainText, 'Fog sits low over the fen.');
  });

  testWidgets('Return splits a paragraph into two blocks', (tester) async {
    final (container, _, _) = await openEditor(
      tester,
      temp,
      seed: seedWith('First. Second.'),
    );

    final field = find.byType(TextField).last;
    await tester.tap(field);
    await tester.pump();

    // Place the caret between the two sentences, then press Return.
    final controller =
        tester.widget<TextField>(field).controller! as RichTextController;
    controller.selection = const TextSelection.collapsed(offset: 7);
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    final document = container.read(documentControllerProvider)!.document;
    expect(document.blocks, hasLength(2));
    expect(document.blocks[0].plainText, 'First. ');
    expect(document.blocks[1].plainText, 'Second.');

    // Settle the pending save so the debounce timer does not outlive the test.
    await tester.runAsync(
      () => container.read(documentControllerProvider.notifier).flush(),
    );
  });

  testWidgets('Windows text modifier keybinds format the selection', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final (container, _, _) = await openEditor(
        tester,
        temp,
        seed: seedWith('The Fen'),
      );
      final field = find.byType(TextField).last;
      await tester.tap(field);
      final controller =
          tester.widget<TextField>(field).controller! as RichTextController;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 3,
      );
      await tester.pump();

      Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(key);
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await press(LogicalKeyboardKey.keyB);
      await press(LogicalKeyboardKey.keyI);
      await press(LogicalKeyboardKey.keyU);
      await press(LogicalKeyboardKey.keyX, shift: true);

      final formatted =
          (container.read(documentControllerProvider)!.document.blocks.first
                  as ParagraphBlock)
              .spans
              .first;
      expect(formatted.text, 'The');
      expect(formatted.bold, isTrue);
      expect(formatted.italic, isTrue);
      expect(formatted.underline, isTrue);
      expect(formatted.strikethrough, isTrue);

      await tester.runAsync(
        () => container.read(documentControllerProvider.notifier).flush(),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('Windows keybinds set and toggle the format for future typing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final (container, _, _) = await openEditor(
        tester,
        temp,
        seed: seedWith('Plain:'),
      );
      final field = find.byType(TextField).last;
      await tester.tap(field);
      final controller =
          tester.widget<TextField>(field).controller! as RichTextController;
      controller.selection = const TextSelection.collapsed(offset: 6);
      await tester.pump();

      Future<void> press(LogicalKeyboardKey key, {bool shift = false}) async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        if (shift) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyEvent(key);
        if (shift) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        }
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await tester.pump();
      }

      await press(LogicalKeyboardKey.keyB);
      await press(LogicalKeyboardKey.keyI);
      await press(LogicalKeyboardKey.keyU);
      await press(LogicalKeyboardKey.keyX, shift: true);

      controller.value = const TextEditingValue(
        text: 'Plain:styled',
        selection: TextSelection.collapsed(offset: 12),
      );
      await tester.pump();

      await press(LogicalKeyboardKey.keyB); // Bold off; the others stay on.
      controller.value = const TextEditingValue(
        text: 'Plain:styled more',
        selection: TextSelection.collapsed(offset: 17),
      );
      await tester.pump();

      final spans =
          (container.read(documentControllerProvider)!.document.blocks.first
                  as ParagraphBlock)
              .spans;
      expect(spans.map((span) => span.text), ['Plain:', 'styled', ' more']);
      expect(spans[1].bold, isTrue);
      expect(spans[1].italic, isTrue);
      expect(spans[1].underline, isTrue);
      expect(spans[1].strikethrough, isTrue);
      expect(spans[2].bold, isFalse);
      expect(spans[2].italic, isTrue);
      expect(spans[2].underline, isTrue);
      expect(spans[2].strikethrough, isTrue);

      await tester.runAsync(
        () => container.read(documentControllerProvider.notifier).flush(),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('a future typing format continues into a new block', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final (container, _, _) = await openEditor(
        tester,
        temp,
        seed: seedWith(''),
      );
      await tester.tap(find.byType(TextField).last);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(find.byType(TextField).last);
      field.controller!.value = const TextEditingValue(
        text: 'Still bold',
        selection: TextSelection.collapsed(offset: 10),
      );
      await tester.pump();

      final document = container.read(documentControllerProvider)!.document;
      expect(document.blocks, hasLength(2));
      expect(
        (document.blocks.last as ParagraphBlock).spans.single.bold,
        isTrue,
      );

      await tester.runAsync(
        () => container.read(documentControllerProvider.notifier).flush(),
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the block model keeps one paragraph per block', (tester) async {
    final (container, _, _) = await openEditor(
      tester,
      temp,
      seed: BlockDocument(
        id: 'doc-1',
        title: 'Aldenmoor',
        blocks: [
          ParagraphBlock(
            id: 'b1',
            spans: const [TextSpanNode(text: 'One')],
          ),
          ParagraphBlock(
            id: 'b2',
            spans: const [TextSpanNode(text: 'Two')],
          ),
          ParagraphBlock(
            id: 'b3',
            spans: const [TextSpanNode(text: 'Three')],
          ),
        ],
      ),
    );

    // Title field plus one field per paragraph block.
    expect(find.byType(TextField), findsNWidgets(4));
    expect(
      container.read(documentControllerProvider)!.document.blocks,
      hasLength(3),
    );
  });

  testWidgets('submitting the title renames the file everywhere', (
    tester,
  ) async {
    final (container, kb, path) = await openEditor(tester, temp);

    await tester.enterText(find.byType(TextField).first, 'The Fen Road');
    await tester.pump();

    await tester.runAsync(() async {
      await tester.testTextInput.receiveAction(TextInputAction.done);
      final renamed = File(kb.absolutePathFor('The Fen Road.md'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (!renamed.existsSync() && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    });
    await tester.pumpAndSettle();

    const renamedPath = 'The Fen Road.md';
    expect(File(kb.absolutePathFor(path)).existsSync(), isFalse);
    expect(File(kb.absolutePathFor(renamedPath)).existsSync(), isTrue);
    final onDisk = await tester.runAsync(() => kb.readDocument(renamedPath));
    expect(onDisk?.title, 'The Fen Road');
    expect(
      container.read(documentControllerProvider)?.relativePath,
      renamedPath,
    );

    final session = container.read(kbSessionProvider)!;
    expect((session.tree.single as KbFile).displayName, 'The Fen Road');
    expect(session.index.search('Aldenmoor'), isEmpty);
    expect(session.index.search('Fen Road').single.relativePath, renamedPath);

    final store = await tester.runAsync(
      () => container.read(appStoreProvider.future),
    );
    final recents = await tester.runAsync(
      () => store!.recentDocuments(session.kb.manifest.kbId),
    );
    expect(recents, contains(renamedPath));
    expect(recents, isNot(contains(path)));
  });

  testWidgets('the title divider is inset and leaves the canvas unchanged', (
    tester,
  ) async {
    await openEditor(tester, temp, brightness: Brightness.light);

    final editor = tester.getRect(find.byType(EditorScreen));
    final title = tester.getRect(find.byType(DocumentTitleField));
    final dividerFinder = find.byKey(const Key('editor-title-content-divider'));
    final divider = tester.getRect(dividerFinder);
    final line = tester.widget<ColoredBox>(dividerFinder);

    expect(divider.top, greaterThan(title.bottom));
    expect(divider.left, greaterThan(editor.left));
    expect(divider.right, lessThan(editor.right));
    expect(divider.height, 1);
    expect(line.color, DsColors.light.border);
    expect(
      Theme.of(tester.element(find.byType(EditorScreen)))
          .extension<DsColors>()!
          .editorSurface,
      DsColors.light.editorSurface,
      reason: 'the title separator does not introduce another surface fill',
    );
  });

  testWidgets('leaving the title field commits its rename', (tester) async {
    String? requested;
    await tester.pumpWidget(
      MaterialApp(
        theme: dsTheme(Brightness.dark),
        home: Scaffold(
          body: Column(
            children: [
              DocumentTitleField(
                key: const Key('title'),
                title: 'Aldenmoor',
                onRename: (title) async {
                  requested = title;
                  return title;
                },
              ),
              const TextField(key: Key('body')),
            ],
          ),
        ),
      ),
    );

    await tester.enterText(find.byKey(const Key('title')), 'The Fen Road');
    await tester.tap(find.byKey(const Key('body')));
    await tester.pumpAndSettle();

    expect(requested, 'The Fen Road');
  });

  group('rich text controller', () {
    test('moving the caret clears an explicit future typing format', () {
      final controller = RichTextController(
        spans: const [TextSpanNode(text: 'Plain')],
      );
      controller.selection = const TextSelection.collapsed(offset: 5);
      controller.setTypingFormat(
        controller.formatForTypingAt(5).copyWith(bold: true),
      );

      expect(controller.formatForTypingAt(5).bold, isTrue);

      controller.selection = const TextSelection.collapsed(offset: 0);

      expect(controller.formatForTypingAt(0).bold, isFalse);
    });

    test('bold applied to a selection survives editing elsewhere', () {
      final controller = RichTextController(
        spans: const [TextSpanNode(text: 'The moor is wide.')],
      );

      // Bold "moor".
      controller.applyToRange(
        const TextRange(start: 4, end: 8),
        (f) => TextSpanNode(
          text: f.text,
          bold: true,
          italic: f.italic,
          strikethrough: f.strikethrough,
          underline: f.underline,
          color: f.color,
          highlight: f.highlight,
          font: f.font,
        ),
      );

      expect(controller.toSpans().where((s) => s.bold).single.text, 'moor');

      // Now rewrite the tail; the bold run must be untouched.
      controller.value = const TextEditingValue(
        text: 'The moor is bitter.',
        selection: TextSelection.collapsed(offset: 19),
      );

      final spans = controller.toSpans();
      expect(spans.map((s) => s.text).join(), 'The moor is bitter.');
      expect(spans.where((s) => s.bold).single.text, 'moor');
    });

    test('typing at the end of a bold run stays bold', () {
      final controller = RichTextController(
        spans: const [
          TextSpanNode(text: 'The '),
          TextSpanNode(text: 'moor', bold: true),
        ],
      );

      controller.value = const TextEditingValue(
        text: 'The moors',
        selection: TextSelection.collapsed(offset: 9),
      );

      expect(controller.toSpans().where((s) => s.bold).single.text, 'moors');
    });

    test('deleting a formatted run removes its formatting too', () {
      final controller = RichTextController(
        spans: const [
          TextSpanNode(text: 'Keep '),
          TextSpanNode(text: 'drop', bold: true),
        ],
      );

      controller.value = const TextEditingValue(
        text: 'Keep ',
        selection: TextSelection.collapsed(offset: 5),
      );

      expect(controller.toSpans().any((s) => s.bold), isFalse);
    });

    test('rangeSatisfies drives toggling rather than only setting', () {
      final controller = RichTextController(
        spans: const [TextSpanNode(text: 'All bold', bold: true)],
      );

      expect(
        controller.rangeSatisfies(
          const TextRange(start: 0, end: 8),
          (f) => f.bold,
        ),
        isTrue,
      );
      expect(
        controller.rangeSatisfies(
          const TextRange(start: 0, end: 8),
          (f) => f.italic,
        ),
        isFalse,
      );
    });

    test(
      'every specified inline format round-trips through the controller',
      () {
        const original = [
          TextSpanNode(text: 'plain '),
          TextSpanNode(
            text: 'everything',
            bold: true,
            italic: true,
            strikethrough: true,
            underline: true,
            color: '#8A3B12',
            highlight: '#F2E7C9',
            font: 'Georgia',
          ),
        ];

        final spans = RichTextController(spans: original).toSpans();
        expect(spans, hasLength(2));
        expect(spans[1].bold, isTrue);
        expect(spans[1].italic, isTrue);
        expect(spans[1].strikethrough, isTrue);
        expect(spans[1].underline, isTrue);
        expect(spans[1].color, '#8A3B12');
        expect(spans[1].highlight, '#F2E7C9');
        expect(spans[1].font, 'Georgia');
      },
    );

    test('a malformed colour is ignored rather than crashing', () {
      expect(parseColor('#GGGGGG'), isNull);
      expect(parseColor('nonsense'), isNull);
      expect(parseColor(null), isNull);
      expect(parseColor('#8A3B12'), const Color(0xFF8A3B12));
    });
  });

  group('Markdown typed at the head of a paragraph', () {
    /// Types [text] into the first block and returns the document.
    Future<BlockDocument> type(WidgetTester tester, String text) async {
      final (container, _, _) = await openEditor(
        tester,
        temp,
        seed: seedWith(''),
      );
      await tester.enterText(find.byType(TextField).last, text);
      await tester.pumpAndSettle();
      final document = container.read(documentControllerProvider)!.document;
      await tester.runAsync(
        () => container.read(documentControllerProvider.notifier).flush(),
      );
      return document;
    }

    testWidgets('"## " becomes a heading', (tester) async {
      final document = await type(tester, '## ');
      final block = document.blocks.first;
      expect(block, isA<HeadingBlock>());
      expect((block as HeadingBlock).level, 2);
      expect(block.plainText, isEmpty, reason: 'the prefix is consumed');
    });

    testWidgets('"- " becomes a bulleted item', (tester) async {
      final block = (await type(tester, '- ')).blocks.first;
      expect(block, isA<ListItemBlock>());
      expect((block as ListItemBlock).style, ListStyle.bullet);
    });

    testWidgets('"1. " becomes a numbered item', (tester) async {
      final block = (await type(tester, '1. ')).blocks.first;
      expect((block as ListItemBlock).style, ListStyle.ordered);
    });

    testWidgets('"> " becomes a quote', (tester) async {
      expect((await type(tester, '> ')).blocks.first, isA<QuoteBlock>());
    });

    testWidgets('the block keeps its id, and so its controller', (
      tester,
    ) async {
      final block = (await type(tester, '# ')).blocks.first;
      expect(block.id, 'b1');
    });

    testWidgets('typing the prefix, then the text, keeps both', (tester) async {
      final (container, _, _) = await openEditor(
        tester,
        temp,
        seed: seedWith(''),
      );
      final field = find.byType(TextField).last;

      await tester.enterText(field, '## ');
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'The Fen');
      await tester.pumpAndSettle();

      final block = container
          .read(documentControllerProvider)!
          .document
          .blocks
          .first;
      expect(block, isA<HeadingBlock>());
      expect(block.plainText, 'The Fen');

      await tester.runAsync(
        () => container.read(documentControllerProvider.notifier).flush(),
      );
    });

    /// enterText replaces the whole field in one go, which is what a paste
    /// looks like. Converting then would rewrite text the user never typed as
    /// a prefix, so it deliberately does not fire.
    testWidgets('a pasted line is left as text', (tester) async {
      final block = (await type(tester, '## The Fen')).blocks.first;
      expect(block, isA<ParagraphBlock>());
      expect(block.plainText, '## The Fen');
    });

    testWidgets('a hash typed mid-line is left alone', (tester) async {
      final block = (await type(tester, 'a # b')).blocks.first;
      expect(block, isA<ParagraphBlock>());
      expect(block.plainText, 'a # b');
    });
  });

  testWidgets('an image caption keeps typed order and its caret', (
    tester,
  ) async {
    final (container, kb, path) = await openEditor(
      tester,
      temp,
      seed: BlockDocument(
        id: 'doc-1',
        title: 'Aldenmoor',
        blocks: [ImageBlock(id: 'img-1', assetId: 'gate.png')],
      ),
    );

    Finder captionField() => find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.hintText == 'Caption',
    );

    final before = tester.widget<TextField>(captionField()).controller;
    await tester.enterText(captionField(), 'Testing');
    await tester.pump();

    final after = tester.widget<TextField>(captionField()).controller;
    expect(
      identical(before, after),
      isTrue,
      reason:
          'a field rebuilt per keystroke resets its caret to the start, '
          'so typed characters prepend themselves ("gnitseT")',
    );
    expect(after!.selection.baseOffset, 'Testing'.length);
    expect(
      container
          .read(documentControllerProvider)!
          .document
          .blocks
          .single
          .plainText,
      'Testing',
    );

    late BlockDocument onDisk;
    await tester.runAsync(() async {
      await container.read(documentControllerProvider.notifier).flush();
      onDisk = await kb.readDocument(path);
    });
    expect(onDisk.blocks.single.plainText, 'Testing');
  });

  testWidgets('insertDivider drops a horizontal rule after the focused block', (
    tester,
  ) async {
    final (container, _, _) = await openEditor(
      tester,
      temp,
      seed: seedWith('Fog sits low.'),
    );

    await tester.tap(find.text('Fog sits low.'));
    await tester.pump();
    container.read(editingFocusProvider.notifier).insertDivider();
    await tester.pumpAndSettle();

    final blocks = container.read(documentControllerProvider)!.document.blocks;
    expect(blocks[0].plainText, 'Fog sits low.');
    expect(blocks[1], isA<DividerBlock>());

    await tester.runAsync(
      () => container.read(documentControllerProvider.notifier).flush(),
    );
  });

  testWidgets('hovering a block reveals an ellipsis whose menu deletes it', (
    tester,
  ) async {
    final (container, _, _) = await openEditor(
      tester,
      temp,
      seed: BlockDocument(
        id: 'doc-1',
        title: 'Aldenmoor',
        blocks: [
          ParagraphBlock(
            id: 'b1',
            spans: [const TextSpanNode(text: 'First.')],
          ),
          // An image keeps the menu short enough that every entry is on
          // screen without scrolling, and exercises Delete image itself.
          ImageBlock(id: 'img-1', assetId: 'gate.png'),
        ],
      ),
    );

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.text('Image missing')));
    await tester.pump();

    expect(find.byKey(const Key('block-hover-grip')), findsOneWidget);
    await tester.tap(find.byKey(const Key('block-hover-grip')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete image'));
    await tester.pumpAndSettle();

    final blocks = container.read(documentControllerProvider)!.document.blocks;
    expect(blocks, hasLength(1));
    expect(blocks.single.id, 'b1');

    await tester.runAsync(
      () => container.read(documentControllerProvider.notifier).flush(),
    );
  });

  testWidgets(
    'Ctrl+S while focused in the title leaves one file, at the renamed path, with the original document ID',
    (tester) async {
      final (container, kb, path) = await openEditor(tester, temp);
      final initialDoc = (await tester.runAsync(() => kb.readDocument(path)))!;
      expect(path, 'Aldenmoor.md');
      expect(File(kb.absolutePathFor('Aldenmoor.md')).existsSync(), isTrue);

      final titleField = find.byType(TextField).first;
      await tester.enterText(titleField, 'Ammur-ili');
      await tester.pump();

      final callbackShortcuts = tester.widget<CallbackShortcuts>(
        find
            .ancestor(of: titleField, matching: find.byType(CallbackShortcuts))
            .first,
      );
      final onSave = callbackShortcuts.bindings.entries
          .firstWhere(
            (e) =>
                e.key is SingleActivator &&
                (e.key as SingleActivator).trigger == LogicalKeyboardKey.keyS,
          )
          .value;

      await tester.runAsync(() async {
        onSave();
        final renamed = File(kb.absolutePathFor('Ammur-ili.md'));
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!renamed.existsSync() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
        await container.read(documentControllerProvider.notifier).flush();
      });
      await tester.pump();

      final tree = await tester.runAsync(kb.readTree);
      final paths = documentPathsIn(tree!).toList();
      expect(paths, ['Ammur-ili.md']);
      expect(File(kb.absolutePathFor('Aldenmoor.md')).existsSync(), isFalse);
      expect(File(kb.absolutePathFor('Ammur-ili.md')).existsSync(), isTrue);

      final renamedDoc = await tester.runAsync(
        () => kb.readDocument('Ammur-ili.md'),
      );
      expect(renamedDoc!.id, initialDoc.id);
      expect(renamedDoc.title, 'Ammur-ili');
    },
  );
}
