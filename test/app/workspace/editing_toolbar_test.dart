/// The formatting toolbar in the bottom bar.
///
/// It reaches the editor across two widget subtrees, so most of what is worth
/// testing is the seam: does it see the right selection, does acting on it
/// leave the caret alone, and does it stay short enough not to move the bar.
library;

import 'dart:io';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/features/editing_toolbar/ui/editing_toolbar.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_fonts.dart';

class ToolbarDocuments extends DocumentRepository {
  ToolbarDocuments({this.currentProtection});

  DocumentProtection? currentProtection;
  BlockDocument? currentDocument;
  String? currentPath;
  String? protectedDocumentId;
  int publishCalls = 0;

  @override
  Future<DocumentProtection?> protection(String documentId) async =>
      currentProtection;

  @override
  Future<RemoteDocumentSnapshot?> snapshotForDocument(
    String documentId,
  ) async => currentDocument?.id != documentId
      ? null
      : RemoteDocumentSnapshot(
          path: currentPath!,
          revisionId: 'base-1',
          document: currentDocument!,
          protection: currentProtection,
        );

  @override
  Future<DocumentPublishReceipt> publishChange({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) async {
    publishCalls++;
    currentDocument = document;
    currentPath = relativePath;
    return const DocumentPublishReceipt.published('revision-2');
  }

  @override
  Future<DocumentProtection?> setProtection({
    required String kbId,
    required String documentId,
    DocumentProtection? protection,
  }) async {
    protectedDocumentId = documentId;
    currentProtection = protection;
    return protection;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadTestFonts);

  late Directory temp;
  late Directory support;

  Finder paragraphField() => find.byWidgetPredicate(
    (widget) => widget is TextField && widget.controller is RichTextController,
    description: 'document paragraph TextField',
  );

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

  /// Opens the shell on the Editor view with one two-paragraph document.
  Future<ProviderContainer> openEditor(
    WidgetTester tester, {
    List<Override> overrides = const [],
    ToolbarDocuments? documents,
  }) async {
    tester.view.physicalSize = const Size(1100, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(overrides: overrides);
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container
          .read(kbControllerProvider.notifier)
          .openFolder(temp.path, createWithName: 'MyWorld');
      final kb = container.read(kbSessionProvider)!.kb;
      final path = await kb.createDocument(title: 'Timeline');
      final document = BlockDocument(
        id: 'd1',
        title: 'Timeline',
        blocks: [
          ParagraphBlock(
            id: 'p1',
            spans: const [TextSpanNode(text: 'The first age ended.')],
          ),
        ],
      );
      await kb.writeDocument(path, document);
      documents
        ?..currentDocument = document
        ..currentPath = path;
      await (await SyncLedger.open(kb)).record(
        document: document,
        revisionId: 'base-1',
        path: path,
        protection: documents?.currentProtection,
      );
      await container.read(kbControllerProvider.notifier).refreshTree();
      await container.read(documentControllerProvider.notifier).open(path);
      container.read(viewProvider.notifier).state = DsView.editor;
    });

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dsTheme(),
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

    final field = tester.widget<TextField>(paragraphField());
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

  testWidgets('protected lower-rank edits show Propose and a locked shield', (
    tester,
  ) async {
    const protection = DocumentProtection(
      protectionClass: DocumentProtectionClass.protected,
      minimumPublishRole: MinimumPublishRole.owner,
    );
    final documents = ToolbarDocuments(currentProtection: protection);
    final container = await openEditor(
      tester,
      documents: documents,
      overrides: [
        kbRoleProvider.overrideWith((ref) async => KbRole.editor),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
    await selectInParagraph(tester, 3);
    await tester.pumpAndSettle();

    expect(find.text('Propose'), findsOneWidget);
    await tester.tap(find.byKey(const Key('document-protection-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('Owner access is required to change this protection.'),
      findsOneWidget,
    );

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await settle(tester, container);
  });

  testWidgets('first protection defaults to the current collaborator rank', (
    tester,
  ) async {
    final documents = ToolbarDocuments();
    final container = await openEditor(
      tester,
      documents: documents,
      overrides: [
        kbRoleProvider.overrideWith((ref) async => KbRole.coOwner),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
    await selectInParagraph(tester, 3);
    await tester.tap(find.byKey(const Key('document-protection-button')));
    await tester.pumpAndSettle();

    final roleField = tester
        .widget<DropdownButtonFormField<MinimumPublishRole>>(
          find.byKey(const Key('minimum-publish-role-field')),
        );
    expect(roleField.initialValue, MinimumPublishRole.coOwner);
    expect(find.text('Owner'), findsNothing);

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await settle(tester, container);
  });

  test('protecting a copied document cannot protect its original', () async {
    final documents = ToolbarDocuments();
    final container = ProviderContainer(
      overrides: [
        kbRoleProvider.overrideWith((ref) => KbRole.owner),
        documentRepositoryProvider.overrideWithValue(documents),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(kbControllerProvider.notifier)
        .openFolder(temp.path, createWithName: 'MyWorld');
    final session = container.read(kbSessionProvider)!;
    final originalPath = await session.kb.createDocument(title: 'Timeline');
    final original = await session.kb.readDocument(originalPath);
    documents
      ..currentDocument = original
      ..currentPath = originalPath;
    await (await SyncLedger.open(session.kb))
        .record(document: original, revisionId: 'base-1', path: originalPath);
    const copyPath = 'Ammur.md';
    await session.kb.writeDocument(
      copyPath,
      BlockDocument(id: original.id, title: 'Ammur', blocks: original.blocks),
    );
    await container.read(kbControllerProvider.notifier).refreshTree();
    await container.read(documentControllerProvider.notifier).open(copyPath);

    await container
        .read(sharingControllerProvider)
        .setDocumentProtection(
          documentId: original.id,
          relativePath: copyPath,
          protection: const DocumentProtection(
            protectionClass: DocumentProtectionClass.protected,
            minimumPublishRole: MinimumPublishRole.owner,
          ),
        );

    final copy = await session.kb.readDocument(copyPath);
    final originalAfter = await session.kb.readDocument(originalPath);
    expect(copy.id, isNot(original.id));
    expect(documents.publishCalls, 1);
    expect(documents.protectedDocumentId, copy.id);
    expect(originalAfter.id, original.id);
  });

  testWidgets('Ctrl+S is bound and Publish stays enabled after editing', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final documents = ToolbarDocuments();
      final container = await openEditor(
        tester,
        documents: documents,
        overrides: [
          kbRoleProvider.overrideWith((ref) async => KbRole.editor),
          documentRepositoryProvider.overrideWithValue(documents),
        ],
      );
      await selectInParagraph(tester, 3);
      final controller =
          tester.widget<TextField>(paragraphField()).controller!
              as RichTextController;
      controller.value = const TextEditingValue(
        text: 'Explicitly published words',
        selection: TextSelection.collapsed(offset: 26),
      );
      await tester.pump();
      expect(
        container.read(documentControllerProvider)!.document.plainText,
        'Explicitly published words',
      );
      expect(
        tester.widget<TextField>(paragraphField()).focusNode?.hasFocus,
        isTrue,
      );

      final hasSaveShortcut = tester
          .widgetList<Shortcuts>(find.byType(Shortcuts))
          .expand((widget) => widget.shortcuts.keys)
          .whereType<SingleActivator>()
          .any(
            (shortcut) =>
                shortcut.trigger == LogicalKeyboardKey.keyS &&
                shortcut.control &&
                !shortcut.meta,
          );
      expect(hasSaveShortcut, isTrue);
      final publishButton = tester.widget<DsButton>(
        find.byKey(const Key('document-publish-button')),
      );
      expect(publishButton.onPressed, isNotNull);
      expect(documents.publishCalls, 0, reason: 'editing alone stays local');
      await settle(tester, container);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the toolbar appears once the caret is in a block', (
    tester,
  ) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);
    expect(find.byType(EditingToolbar), findsOneWidget);
    await settle(tester, container);
  });

  testWidgets('its island follows the editor width while buttons stay intact', (
    tester,
  ) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    final editorIsland = find.ancestor(
      of: find.byType(EditorScreen),
      matching: find.byType(DsPane),
    );
    final toolbarIsland = find.byKey(const Key('editing-toolbar-island'));

    Rect editorRect() => tester.getRect(editorIsland);
    Rect toolbarRect() => tester.getRect(toolbarIsland);

    expect(toolbarRect().left, editorRect().left);
    expect(toolbarRect().right, editorRect().right);
    expect(
      find.ancestor(
        of: find.byIcon(Icons.format_bold),
        matching: find.byType(DsButton),
      ),
      findsOneWidget,
      reason: 'wrapping the toolbar must not flatten its buttons',
    );

    final editorBefore = editorRect();
    final toolbarBefore = toolbarRect();
    await tester.dragFrom(
      Offset(
        editorBefore.right + DsSpace.seam / 2,
        editorBefore.center.dy,
      ),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();

    final editorAfter = editorRect();
    final toolbarAfter = toolbarRect();
    expect(editorAfter.width, isNot(editorBefore.width));
    expect(toolbarAfter.width, editorAfter.width);
    expect(
      toolbarAfter.width - toolbarBefore.width,
      closeTo(editorAfter.width - editorBefore.width, 0.5),
    );

    // Let the persisted pane-width debounce finish before disposing the test
    // container.
    await tester.pump(const Duration(milliseconds: 450));
    await settle(tester, container);
  });

  testWidgets('Differences lives in the toolbar ellipsis menu', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    expect(find.text('Differences'), findsOneWidget);
    expect(find.byKey(const Key('document-publish-button')), findsOneWidget);
    expect(find.byKey(const Key('document-protection-button')), findsOneWidget);
    await tester.tap(find.byTooltip('Editor menu'));
    await tester.pumpAndSettle();

    expect(find.text('Publish directly'), findsNothing);
    expect(find.text('Sync latest'), findsNothing);
    expect(find.byKey(const Key('editor-menu-differences')), findsOneWidget);
    expect(find.text('Differences'), findsNWidgets(2));
    expect(
      tester
          .widget<Tooltip>(
            find.descendant(
              of: find.byKey(const Key('editor-menu-differences')),
              matching: find.byType(Tooltip),
            ),
          )
          .message,
      'No pending edits for this document.',
    );

    await tester.tapAt(const Offset(1, 1));
    await tester.pumpAndSettle();
    await settle(tester, container);
  });

  testWidgets('text modifier tooltips show their Windows keybinds', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      final container = await openEditor(tester);
      await selectInParagraph(tester, 3);

      for (final (icon, message) in const [
        (Icons.format_bold, 'Bold (CTRL + B)'),
        (Icons.format_italic, 'Italics (CTRL + I)'),
        (Icons.format_underlined, 'Underline (CTRL + U)'),
        (Icons.format_strikethrough, 'Strikethrough (CTRL + SHIFT + X)'),
      ]) {
        final tooltip = tester.widget<Tooltip>(
          find.ancestor(of: find.byIcon(icon), matching: find.byType(Tooltip)),
        );
        expect(tooltip.message, message);
      }

      await settle(tester, container);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the island leaves breathing room around every button', (
    tester,
  ) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    final island = tester.getRect(
      find.byKey(const Key('editing-toolbar-island')),
    );
    final toolbar = tester.getRect(find.byType(EditingToolbar));
    final menu = tester.getRect(find.byType(EditorToolbarMenuButton));

    expect(toolbar.height, lessThanOrEqualTo(menu.height));
    expect(toolbar.top - island.top, greaterThanOrEqualTo(6));
    expect(island.bottom - toolbar.bottom, greaterThanOrEqualTo(6));
    expect(menu.top - island.top, greaterThanOrEqualTo(6));
    expect(island.bottom - menu.bottom, greaterThanOrEqualTo(6));
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

    final bold = tester.widget<DsButton>(
      find.ancestor(
        of: find.byIcon(Icons.format_bold),
        matching: find.byType(DsButton),
      ),
    );
    expect(bold.active, isTrue);

    await settle(tester, container);
  });

  testWidgets('format buttons set the format for text typed at the caret', (
    tester,
  ) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 0); // collapsed caret

    final bold = tester.widget<DsButton>(
      find.ancestor(
        of: find.byIcon(Icons.format_bold),
        matching: find.byType(DsButton),
      ),
    );
    expect(bold.onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(paragraphField());
    final controller = field.controller! as RichTextController;
    controller.value = TextEditingValue(
      text: 'A${controller.text}',
      selection: const TextSelection.collapsed(offset: 1),
    );
    await tester.pumpAndSettle();

    final firstSpan =
        (container.read(documentControllerProvider)!.document.blocks.first
                as ParagraphBlock)
            .spans
            .first;
    expect(firstSpan.text, 'A');
    expect(firstSpan.bold, isTrue);

    // Alignment acts on the block, so it stays available.
    expect(find.byType(DsSegmented<BlockAlign>), findsOneWidget);
    await tester.tap(find.byIcon(Icons.format_align_center));
    await tester.pumpAndSettle();
    expect(
      (container.read(documentControllerProvider)!.document.blocks.first
              as ParagraphBlock)
          .align,
      BlockAlign.center,
    );

    await settle(tester, container);
  });

  testWidgets('pressing a toolbar button does not steal focus', (tester) async {
    final container = await openEditor(tester);
    await selectInParagraph(tester, 3);

    final before = tester.widget<TextField>(paragraphField());
    expect(before.focusNode!.hasFocus, isTrue);

    await tester.tap(find.byIcon(Icons.format_bold));
    await tester.pumpAndSettle();

    final after = tester.widget<TextField>(paragraphField());
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

    await tester.tap(find.byIcon(Icons.title));
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

    await tester.tap(find.byIcon(Icons.title));
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
