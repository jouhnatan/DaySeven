/// The formatting toolbar in the bottom bar.
///
/// It reaches the editor across two widget subtrees, so most of what is worth
/// testing is the seam: does it see the right selection, does acting on it
/// leave the caret alone, and does it stay short enough not to move the bar.
library;

import 'dart:io';

import 'package:dayseven/app/service.dart';
import 'package:dayseven/app/shell/editing_toolbar.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);

  late Directory temp;
  late Directory support;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_toolbar');
    support = await Directory.systemTemp.createTemp('dayseven_toolbar_support');
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

  /// Opens the shell on the Editor service with one two-paragraph document.
  Future<ProviderContainer> openEditor(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container
          .read(kbControllerProvider.notifier)
          .openFolder(temp.path, createWithName: 'MyWorld');
      final kb = container.read(kbSessionProvider)!.kb;
      final path = await kb.createDocument(title: 'Timeline');
      await kb.writeDocument(
        path,
        BlockDocument(
          id: 'd1',
          title: 'Timeline',
          blocks: [
            ParagraphBlock(
              id: 'p1',
              spans: const [TextSpanNode(text: 'The first age ended.')],
            ),
          ],
        ),
      );
      await container.read(kbControllerProvider.notifier).refreshTree();
      await container.read(documentControllerProvider.notifier).open(path);
      container.read(serviceProvider.notifier).state = DsService.editor;
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dsTheme(Brightness.light),
          home: const DsShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  /// Puts the caret in the paragraph and selects [length] characters.
  Future<void> selectInParagraph(WidgetTester tester, int length) async {
    await tester.tap(find.text('The first age ended.'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(find.byType(TextField).last);
    field.controller!.selection = TextSelection(
      baseOffset: 0,
      extentOffset: length,
    );
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester, ProviderContainer container) async {
    await tester.pumpAndSettle();
    await tester.runAsync(
      () => container.read(documentControllerProvider.notifier).flush(),
    );
  }

  testWidgets('there is no toolbar until something is being edited', (
    tester,
  ) async {
    await openEditor(tester);
    expect(find.byType(EditingToolbar), findsNothing);
  });

  testWidgets('the toolbar appears once the caret is in a block', (
    tester,
  ) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);
    expect(find.byType(EditingToolbar), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('it never grows taller than Differences', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    final toolbar = tester.getRect(find.byType(EditingToolbar));
    final differences = tester.getRect(find.byType(DifferencesButton));

    expect(
      toolbar.height,
      lessThanOrEqualTo(differences.height),
      reason:
          'a taller toolbar would recentre the bar and move Differences, '
          'which two shell tests measure their spacing from',
    );
    await settle(tester, container);
  });

  testWidgets('bold applies to the selection', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pumpAndSettle();

    final block =
        container.read(documentControllerProvider)!.document.blocks.first
            as ParagraphBlock;
    expect(block.spans.first.text, 'The');
    expect(block.spans.first.bold, isTrue);
    expect(block.spans[1].bold, isFalse, reason: 'only the selection');

    await settle(tester, container);
  });

  testWidgets('a format button reads as active once it is on', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pumpAndSettle();

    final bold = tester.widget<RoundedControl>(
      find.ancestor(
        of: find.byIcon(Icons.format_bold),
        matching: find.byType(RoundedControl),
      ),
    );
    expect(bold.active, isTrue);

    await settle(tester, container);
  });

  testWidgets('format buttons are disabled with nothing selected', (
    tester,
  ) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 0); // collapsed caret

    final bold = tester.widget<RoundedControl>(
      find.ancestor(
        of: find.byIcon(Icons.format_bold),
        matching: find.byType(RoundedControl),
      ),
    );
    expect(bold.onPressed, isNull);

    // Alignment acts on the block, so it stays available.
    final left = tester.widget<RoundedControl>(
      find.ancestor(
        of: find.byIcon(Icons.format_align_left),
        matching: find.byType(RoundedControl),
      ),
    );
    expect(left.onPressed, isNotNull);

    await settle(tester, container);
  });

  testWidgets('pressing a toolbar button does not steal focus', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    final before = tester.widget<TextField>(find.byType(TextField).last);
    expect(before.focusNode!.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pumpAndSettle();

    final after = tester.widget<TextField>(find.byType(TextField).last);
    expect(
      after.focusNode!.hasFocus,
      isTrue,
      reason: 'the caret, the selection and the focus wash all depend on this',
    );

    await settle(tester, container);
  });

  testWidgets('alignment applies to the focused block', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    await tester.tap(find.byIcon(Icons.format_align_center));
    await tester.pumpAndSettle();

    expect(
      container.read(documentControllerProvider)!.document.blocks.first.align,
      BlockAlign.center,
    );

    await settle(tester, container);
  });

  testWidgets('the heading control turns a paragraph into a heading, keeping '
      'its id and its text', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 2'));
    await tester.pumpAndSettle();

    final block = container
        .read(documentControllerProvider)!
        .document
        .blocks
        .first;
    expect(block, isA<HeadingBlock>());
    expect((block as HeadingBlock).level, 2);
    expect(block.id, 'p1', reason: 'the merge aligns blocks by id');
    expect(block.plainText, 'The first age ended.');

    // And the control now reports the level.
    expect(find.text('H2'), findsOneWidget);

    await settle(tester, container);
  });

  testWidgets('a heading can be turned back into body text', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    await tester.tap(find.text('Body'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Heading 1'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('H1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body text'));
    await tester.pumpAndSettle();

    expect(
      container.read(documentControllerProvider)!.document.blocks.first,
      isA<ParagraphBlock>(),
    );

    await settle(tester, container);
  });
}
