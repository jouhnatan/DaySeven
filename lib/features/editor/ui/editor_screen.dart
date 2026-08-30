/// The editing surface.
///
/// Content is a column of blocks; each paragraph is its own block, so pressing
/// Return starts a new one and Backspace at the head of a block merges it into
/// the one above. Formatting comes from three places: the toolbar in the bottom
/// bar, keyboard shortcuts, and a context menu on the block for the rest —
/// colour, highlight, font, spacing, images and export.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/core/keybinds/data/keybind_hash_map.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/presence.dart';
import 'package:dayseven/shared/presence/peer_presence.dart';
import 'package:dayseven/shared/ui/presence_dots.dart';
import 'package:dayseven/app/workspace/document_publish_controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/documents/documents.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/block_text_style.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';

const double kEditorSearchCardHeight = 58;

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key, this.searchCard, this.timelineWidget});

  /// Injected by the app composition root so Editor does not depend directly
  /// on the separate Search feature.
  final Widget? searchCard;

  /// Injected by the app composition root for the Timeline feature.
  final Widget? timelineWidget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(documentControllerProvider);
    final readOnly = ref.watch(kbRoleProvider).valueOrNull == KbRole.reviewer;

    final editor = open == null
        ? Center(
            child: Text(
              'Open a document from the Knowledge Base.',
              style: uiTextStyle(size: 13, color: colors.muted),
            ),
          )
        // A path can change while this document remains open. Its stable id
        // keeps the editing surface and caret alive through a rename or move.
        : DocumentEditor(
            key: ValueKey(open.document.id),
            open: open,
            readOnly: readOnly,
          );

    final content = (timelineWidget != null && open != null)
        ? Column(
            children: [
              timelineWidget!,
              Expanded(child: editor),
            ],
          )
        : editor;

    final card = searchCard;
    if (card == null) return content;

    // Search stays fixed at the bottom Z layer while the document scrolls
    // independently above it.
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(bottom: kEditorSearchCardHeight, child: content),
        Align(
          alignment: Alignment.bottomCenter,
          child: _EditorSearchCard(child: card),
        ),
      ],
    );
  }
}

class _EditorSearchCard extends StatelessWidget {
  const _EditorSearchCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: kEditorSearchCardHeight,
      width: double.infinity,
      child: DsCard(
        key: const Key('editor-search-card'),
        separator: DsCardSeparator.top,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Center(child: child),
        ),
      ),
    );
  }
}

class DocumentEditor extends ConsumerStatefulWidget {
  const DocumentEditor({super.key, required this.open, this.readOnly = false});

  final OpenDocument open;
  final bool readOnly;

  @override
  ConsumerState<DocumentEditor> createState() => _DocumentEditorState();
}

class _DocumentEditorState extends ConsumerState<DocumentEditor>
    implements EditingSurface {
  /// One controller and focus node per text block, keyed by block id, so that
  /// adding or removing a block does not disturb the others — and so that
  /// turning a paragraph into a heading keeps the very same controller, with
  /// all of its per-character formatting intact.
  final _controllers = <String, RichTextController>{};
  final _focusNodes = <String, FocusNode>{};

  late BlockDocument _document;

  /// The last range the user actually selected in each block. A toolbar click
  /// should not need it — the buttons are not focusable — but if a platform
  /// does move focus, this is what the format still applies to.
  final _lastSelection = <String, TextSelection>{};

  /// Held rather than read through `ref` each time, because `ref` is off
  /// limits by the time [dispose] runs and that is where the detach belongs.
  late final EditingFocusController _editingFocus;

  @override
  void initState() {
    super.initState();
    _document = widget.open.document;
    _editingFocus = ref.read(editingFocusProvider.notifier)..attach(this);
  }

  @override
  void didUpdateWidget(DocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _document = widget.open.document;
  }

  @override
  void dispose() {
    _editingFocus.detach(this);
    for (final c in _controllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  RichTextController _controllerFor(TextBlock block) =>
      _controllers.putIfAbsent(block.id, () {
        final controller = RichTextController(spans: block.spans);
        controller.addListener(() {
          _onParagraphChanged(block.id);
          // The controller notifies on selection changes too, so this is also
          // how the toolbar learns what is selected.
          _publishFocus(block.id);
        });
        return controller;
      });

  /// One controller per cell, keyed by block id and position so a table's
  /// cells behave like any other block: independent, and undisturbed by edits
  /// elsewhere in the table.
  RichTextController _cellControllerFor(TableBlock block, int row, int col) =>
      _controllers.putIfAbsent('${block.id}:$row:$col', () {
        final controller = RichTextController(spans: block.rows[row][col]);
        controller.addListener(() => _onCellChanged(block.id, row, col));
        return controller;
      });

  void _onCellChanged(String blockId, int row, int col) {
    final controller = _controllers['$blockId:$row:$col'];
    if (controller == null) return;

    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _document.blocks[index];
    if (block is! TableBlock) return;

    final blocks = [..._document.blocks];
    blocks[index] = block.withCell(row, col, controller.toSpans());
    _commit(_document.copyWith(blocks: blocks), rebuild: false);
  }

  FocusNode _focusFor(String blockId) => _focusNodes.putIfAbsent(blockId, () {
    final node = FocusNode(onKeyEvent: _handleDocumentShortcut);
    node.addListener(() => _publishFocus(blockId));
    return node;
  });

  KeyEventResult _handleDocumentShortcut(FocusNode node, KeyEvent event) {
    if (widget.readOnly || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    final modifier = defaultTargetPlatform == TargetPlatform.macOS
        ? keyboard.isMetaPressed
        : keyboard.isControlPressed;
    if (event.logicalKey != LogicalKeyboardKey.keyS || !modifier) {
      return KeyEventResult.ignored;
    }
    unawaited(publishOpenDocumentFromShortcut(context, ref));
    return KeyEventResult.handled;
  }

  /// Tells the toolbar what it is pointed at.
  ///
  /// Deferred to after the frame: this runs from listeners registered while
  /// building, and writing to a provider during build throws.
  void _publishFocus(String blockId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // Losing focus deliberately leaves the last block published. Opening the
      // toolbar's own heading menu takes focus away from the editor, and a
      // toolbar that cleared itself then would vanish mid-interaction and have
      // nothing left to act on when the menu closed. The editor's own dispose
      // is what clears it.
      final node = _focusNodes[blockId];
      if (node == null || !node.hasFocus) return;

      final controller = _controllers[blockId];
      final block = _document.blocks.where((b) => b.id == blockId).firstOrNull;
      if (controller == null || block == null) return;

      final selection = controller.selection;
      final has = selection.isValid && !selection.isCollapsed;
      if (has) _lastSelection[blockId] = selection;

      _editingFocus.publish(
        EditingFocus(
          blockId: blockId,
          hasSelection: has,
          caretOffset: selection.isValid ? selection.extentOffset : null,
          selectionAnchorOffset:
              has ? selection.baseOffset : null,
          activeFormats: {
            for (final format in EditingFormat.values)
              if (controller.isFormatActive(format, selection)) format,
          },
          align: block.align,
          headingLevel: block is HeadingBlock ? block.level : null,
        ),
      );
    });
  }

  // ------------------------------------------------- toolbar (EditingSurface) --

  @override
  void toggleFormat(EditingFormat format) {
    final focus = ref.read(editingFocusProvider);
    if (focus == null) return;
    final controller = _controllers[focus.blockId];
    if (controller == null) return;

    final currentSelection = controller.selection;
    final selection =
        focus.hasSelection &&
            (!currentSelection.isValid || currentSelection.isCollapsed)
        ? _lastSelection[focus.blockId]
        : currentSelection;
    if (selection == null || !selection.isValid) return;

    controller.toggleFormat(format, selection);

    // Put the caret back where it was, so typing carries on in place.
    controller.selection = selection;
    _focusFor(focus.blockId).requestFocus();
  }

  @override
  void setAlign(BlockAlign align) {
    final focus = ref.read(editingFocusProvider);
    if (focus == null) return;
    _updateBlock(focus.blockId, (b) => b.copyWithCommon(align: align));
    _publishFocus(focus.blockId);
  }

  @override
  void setHeadingLevel(int? level) {
    final focus = ref.read(editingFocusProvider);
    if (focus == null) return;

    _updateBlock(focus.blockId, (b) {
      if (b is! TextBlock) return b;
      // The id is kept, so the block's controller — and every per-character
      // format in it — survives the change of kind.
      return level == null
          ? ParagraphBlock(
              id: b.id,
              spans: b.spans,
              align: b.align,
              spaceBefore: b.spaceBefore,
            )
          : HeadingBlock(
              id: b.id,
              level: level,
              spans: b.spans,
              align: b.align,
              spaceBefore: b.spaceBefore,
            );
    });

    _focusFor(focus.blockId).requestFocus();
    _publishFocus(focus.blockId);
  }

  @override
  void insertImage() {
    if (widget.readOnly) return;
    final focus = ref.read(editingFocusProvider);
    final afterId = focus?.blockId;
    if (afterId != null &&
        _document.blocks.any((block) => block.id == afterId)) {
      unawaited(_insertImage(afterId));
      return;
    }
    if (_document.blocks.isNotEmpty) {
      unawaited(_insertImage(_document.blocks.last.id));
      return;
    }
    unawaited(_insertImageAtEnd());
  }

  @override
  void insertDivider() {
    if (widget.readOnly) return;
    final divider = DividerBlock(id: newId());
    final focus = ref.read(editingFocusProvider);
    final afterId = focus?.blockId;
    if (afterId != null &&
        _document.blocks.any((block) => block.id == afterId)) {
      _insertAfter(afterId, divider);
      return;
    }
    if (_document.blocks.isNotEmpty) {
      _insertAfter(_document.blocks.last.id, divider);
      return;
    }
    _commit(_document.copyWith(blocks: [divider]));
  }

  /// An ordered item's number, counted from the start of the run it belongs
  /// to, so inserting a line renumbers the ones below it.
  int _ordinalOf(ListItemBlock item) {
    final index = _document.blocks.indexOf(item);
    var n = 1;
    for (var i = index - 1; i >= 0; i--) {
      final previous = _document.blocks[i];
      if (previous is! ListItemBlock) break;
      if (previous.depth < item.depth) break;
      if (previous.depth > item.depth) continue;
      if (previous.style != ListStyle.ordered) break;
      n++;
    }
    return n;
  }

  void _commit(BlockDocument document, {bool rebuild = true}) {
    if (widget.readOnly) return;
    _document = document;
    ref.read(documentControllerProvider.notifier).edit(document);
    if (rebuild && mounted) setState(() {});
  }

  Future<String?> _renameTitle(String title) async {
    if (widget.readOnly) return _document.title;
    try {
      final destination = await ref
          .read(kbControllerProvider.notifier)
          .renameDocument(widget.open.relativePath, title);
      return documentTitleFromPath(destination);
    } catch (error) {
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.error, '$error');
      return null;
    }
  }

  void _onParagraphChanged(String blockId) {
    final controller = _controllers[blockId];
    if (controller == null) return;

    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _document.blocks[index];
    if (block is! TextBlock) return;

    if (_autoformat(index, block, controller)) return;

    final spans = controller.toSpans();
    final blocks = [..._document.blocks];
    blocks[index] = block.withSpans(spans);
    // No rebuild: the field is already showing this text.
    _commit(_document.copyWith(blocks: blocks), rebuild: false);
  }

  /// Turns a Markdown prefix typed at the head of a paragraph into the block
  /// it describes: `## `, `- `, `1. `, `> `.
  ///
  /// Only fires with the caret sitting right after the prefix — that is, the
  /// moment the space is typed — so the same characters typed anywhere else,
  /// or pasted in, are left as text.
  bool _autoformat(int index, TextBlock block, RichTextController controller) {
    if (block is! ParagraphBlock) return false;

    final selection = controller.selection;
    if (!selection.isCollapsed || !selection.isValid) return false;

    final text = controller.text;
    final match = _autoformatPattern.firstMatch(text);
    if (match == null) return false;

    final prefix = match.group(1)!;
    if (selection.baseOffset != prefix.length) return false;

    final rest = _sliceSpans(controller.toSpans(), prefix.length, text.length);
    final Block replacement = switch (prefix.trim()) {
      '>' => QuoteBlock(
        id: block.id,
        spans: rest,
        align: block.align,
        spaceBefore: block.spaceBefore,
      ),
      '-' || '*' || '+' => ListItemBlock(
        id: block.id,
        spans: rest,
        align: block.align,
        spaceBefore: block.spaceBefore,
      ),
      final p when p.startsWith('#') => HeadingBlock(
        id: block.id,
        level: p.length,
        spans: rest,
        align: block.align,
        spaceBefore: block.spaceBefore,
      ),
      _ => ListItemBlock(
        id: block.id,
        spans: rest,
        style: ListStyle.ordered,
        align: block.align,
        spaceBefore: block.spaceBefore,
      ),
    };

    controller.setSpans(rest);
    controller.selection = const TextSelection.collapsed(offset: 0);

    final blocks = [..._document.blocks];
    blocks[index] = replacement;
    _commit(_document.copyWith(blocks: blocks));
    return true;
  }

  /// Replaces the focused block with one of another kind, keeping its id — and
  /// therefore its controller and everything the merge knows about it.
  void _convertBlock(String blockId, Block Function(TextBlock) build) {
    _updateBlock(blockId, (b) => b is TextBlock ? build(b) : b);
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusFor(blockId).requestFocus(),
    );
  }

  void _insertAfter(String afterBlockId, Block block) {
    final index = _document.blocks.indexWhere((b) => b.id == afterBlockId);
    if (index < 0) return;
    final blocks = [..._document.blocks]..insert(index + 1, block);
    _commit(_document.copyWith(blocks: blocks));
  }

  void _insertTable(String afterBlockId) {
    List<TextSpanNode> cell() => const [];
    _insertAfter(
      afterBlockId,
      TableBlock(
        id: newId(),
        rows: [
          [cell(), cell()],
          [cell(), cell()],
        ],
      ),
    );
  }

  void _addTableRow(String blockId) => _updateBlock(blockId, (b) {
    final t = b as TableBlock;
    return t.copyWith(
      rows: [
        ...t.rows,
        [for (var c = 0; c < t.columnCount; c++) const <TextSpanNode>[]],
      ],
    );
  });

  void _addTableColumn(String blockId) => _updateBlock(blockId, (b) {
    final t = b as TableBlock;
    return t.copyWith(
      rows: [
        for (final row in t.rows) [...row, const <TextSpanNode>[]],
      ],
    );
  });

  /// Puts a reference at the caret and its note at the end of the document.
  void _insertFootnote(String blockId) {
    final controller = _controllers[blockId];
    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (controller == null || index < 0) return;

    final used = <String>{
      for (final b in _document.blocks)
        if (b is FootnoteBlock) b.label,
    };
    var n = 1;
    while (used.contains('$n')) {
      n++;
    }
    final label = '$n';

    final at = controller.selection.isValid
        ? controller.selection.end
        : controller.text.length;
    final spans = controller.toSpans();
    final marker = TextSpanNode(text: '[^$label]', footnote: label);
    final rebuilt = [
      ..._sliceSpans(spans, 0, at),
      marker,
      ..._sliceSpans(spans, at, controller.text.length),
    ];

    controller.setSpans(rebuilt);

    final block = _document.blocks[index] as TextBlock;
    final blocks = [..._document.blocks]
      ..[index] = block.withSpans(rebuilt)
      ..add(FootnoteBlock(id: newId(), label: label, spans: const []));
    _commit(_document.copyWith(blocks: blocks));
  }

  Future<void> _insertImageUrl(String afterBlockId) async {
    final field = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (context) => DsDialog(
        actions: [
          DsDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
            tone: DsDialogActionTone.muted,
          ),
          DsDialogAction(
            label: 'Insert',
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
          ),
        ],
        children: [DsField(controller: field, hint: 'https://…/image.png')],
      ),
    );

    if (url == null || url.isEmpty) return;
    _insertAfter(afterBlockId, ImageBlock(id: newId(), url: url));
  }

  Future<void> _setLink(String blockId) async {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final range = TextRange(start: selection.start, end: selection.end);
    final existing = controller.formatAt(selection.start)?.href;
    final field = TextEditingController(text: existing ?? '');

    final url = await showDialog<String>(
      context: context,
      builder: (context) => DsDialog(
        actions: [
          if (existing != null)
            DsDialogAction(
              label: 'Remove',
              onPressed: () => Navigator.of(context).pop(''),
              tone: DsDialogActionTone.muted,
            ),
          DsDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
            tone: DsDialogActionTone.muted,
          ),
          DsDialogAction(
            label: 'Link',
            onPressed: () => Navigator.of(context).pop(field.text.trim()),
          ),
        ],
        children: [DsField(controller: field, hint: 'https://…')],
      ),
    );

    if (url == null) return;
    controller.applyToRange(
      range,
      (f) => _withHref(f, url.isEmpty ? null : url),
    );
    _focusFor(blockId).requestFocus();
  }

  // --------------------------------------------------------- block editing --

  void _splitBlock(String blockId) {
    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final controller = _controllers[blockId]!;
    final typingFormat = controller.explicitTypingFormat;
    final offset = controller.selection.baseOffset.clamp(
      0,
      controller.text.length,
    );

    final spans = controller.toSpans();
    final head = _sliceSpans(spans, 0, offset);
    final tail = _sliceSpans(spans, offset, controller.text.length);

    final block = _document.blocks[index] as TextBlock;
    // Return at the end of a heading starts body text; splitting one in the
    // middle leaves two headings.
    final newBlock = block is HeadingBlock && offset < controller.text.length
        ? HeadingBlock(id: newId(), level: block.level, spans: tail)
        : ParagraphBlock(id: newId(), spans: tail);

    controller.setSpans(head);
    controller.selection = TextSelection.collapsed(
      offset: controller.text.length,
    );

    final blocks = [..._document.blocks];
    blocks[index] = block.withSpans(head);
    blocks.insert(index + 1, newBlock);
    _commit(_document.copyWith(blocks: blocks));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusFor(newBlock.id).requestFocus();
      final c = _controllers[newBlock.id];
      if (c != null) {
        c.selection = const TextSelection.collapsed(offset: 0);
        if (typingFormat != null) c.setTypingFormat(typingFormat);
      }
    });
  }

  /// Backspace at the very start of a block merges it into the block above.
  bool _mergeIntoPrevious(String blockId) {
    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index <= 0) return false;

    final previous = _document.blocks[index - 1];
    final current = _document.blocks[index];
    if (previous is! TextBlock || current is! TextBlock) return false;

    final previousController = _controllerFor(previous);
    final currentController = _controllerFor(current);
    final joinOffset = previousController.text.length;

    final merged = [
      ...previousController.toSpans(),
      ...currentController.toSpans(),
    ];

    previousController.setSpans(merged);
    previousController.selection = TextSelection.collapsed(offset: joinOffset);

    final blocks = [..._document.blocks]
      ..[index - 1] = previous.withSpans(previousController.toSpans())
      ..removeAt(index);

    _controllers.remove(blockId)?.dispose();
    _focusNodes.remove(blockId)?.dispose();
    _commit(_document.copyWith(blocks: blocks));

    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusFor(previous.id).requestFocus(),
    );
    return true;
  }

  void _updateBlock(String blockId, Block Function(Block) transform) {
    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final blocks = [..._document.blocks];
    blocks[index] = transform(blocks[index]);
    _commit(_document.copyWith(blocks: blocks));
  }

  /// Removes one block and everything in it. Asset files stay on disk; only
  /// the document's reference to them goes.
  void _deleteBlock(String blockId) {
    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final blocks = [..._document.blocks]..removeAt(index);
    _controllers.remove(blockId)?.dispose();
    _focusNodes.remove(blockId)?.dispose();
    _commit(_document.copyWith(blocks: blocks));
  }

  Future<void> _insertImage(String afterBlockId) async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'tiff'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    try {
      final assetId = await session.kb.importAsset(File(file.path));
      final index = _document.blocks.indexWhere((b) => b.id == afterBlockId);
      final insertAt = index < 0 ? _document.blocks.length : index + 1;
      final blocks = [..._document.blocks]
        ..insert(insertAt, ImageBlock(id: newId(), assetId: assetId));
      _commit(_document.copyWith(blocks: blocks));
    } on Object catch (error) {
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.error, '$error');
    }
  }

  Future<void> _insertImageAtEnd() async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'tiff'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    try {
      final assetId = await session.kb.importAsset(File(file.path));
      final blocks = [
        ..._document.blocks,
        ImageBlock(id: newId(), assetId: assetId),
      ];
      _commit(_document.copyWith(blocks: blocks));
    } on Object catch (error) {
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.error, '$error');
    }
  }

  Future<void> _export(DocumentFormat format) async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    final extension = format == DocumentFormat.docx ? 'docx' : 'odt';
    final title = _document.title.isEmpty ? 'Untitled' : _document.title;
    final location = await getSaveLocation(
      suggestedName: '$title.$extension',
      acceptedTypeGroups: [
        XTypeGroup(label: extension.toUpperCase(), extensions: [extension]),
      ],
    );
    if (location == null) return;

    // Everything typed so far belongs in the exported file.
    await ref.read(documentControllerProvider.notifier).flush();
    await exportDocumentTo(session.kb, _document, File(location.path));
  }

  // -------------------------------------------------------------- shortcuts --

  void _toggle(String blockId, EditingFormat format) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    controller.toggleFormat(format, selection);
  }

  void _setColor(String blockId, String? color, {required bool highlight}) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    controller.applyToRange(
      TextRange(start: selection.start, end: selection.end),
      (f) => highlight ? _withHighlight(f, color) : _withColor(f, color),
    );
  }

  void _setFont(String blockId, String? font) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    controller.applyToRange(
      TextRange(start: selection.start, end: selection.end),
      (f) => _withFont(f, font),
    );
  }

  // ------------------------------------------------------------------ build --

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    // Read once here and passed down, rather than watched per block: a
    // collaborator moving should repaint two blocks, not the whole document.
    final peersByBlockId = ref.watch(peersByBlockProvider);

    return Focus(
      onKeyEvent: (node, event) => KeyEventResult.ignored,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(48, 40, 48, 120),
        children: [
          AbsorbPointer(
            absorbing: widget.readOnly,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DocumentTitleField(
                title: _document.title,
                onRename: _renameTitle,
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: SizedBox(
              height: 1,
              child: ColoredBox(
                key: const Key('editor-title-content-divider'),
                color: colors.border,
              ),
            ),
          ),
          const SizedBox(height: 20),
          for (final block in _document.blocks)
            AbsorbPointer(
              absorbing: widget.readOnly,
              child: Padding(
                padding: EdgeInsets.only(top: block.spaceBefore),
                child: _BlockHoverGrip(
                  enabled: !widget.readOnly,
                  peers: peersByBlockId[block.id] ?? const [],
                  onMenu: (position) => _showBlockMenu(position, block),
                  child: switch (block) {
                    // Headings differ from paragraphs only in the style the text
                    // sits on, so both use the same view and the same controller.
                    final TextBlock t => _TextBlockView(
                      block: t,
                      controller: _controllerFor(t),
                      focusNode: _focusFor(t.id),
                      style: t is HeadingBlock
                          ? headingStyle(t.level, colors.text)
                          : editorTextStyle(
                              size: 15,
                              height: 1.6,
                              color: colors.text,
                            ),
                      ordinal:
                          t is ListItemBlock && t.style == ListStyle.ordered
                          ? _ordinalOf(t)
                          : null,
                      onToggleChecked: t is ListItemBlock && t.checked != null
                          ? () => _updateBlock(
                              t.id,
                              (b) => (b as ListItemBlock).copyWith(
                                checked: !(b.checked ?? false),
                              ),
                            )
                          : null,
                      onSplit: () => _splitBlock(t.id),
                      onMergeBack: () => _mergeIntoPrevious(t.id),
                      onMenu: (position) => _showBlockMenu(position, t),
                      onPublish: () => unawaited(
                        publishOpenDocumentFromShortcut(context, ref),
                      ),
                    ),
                    CodeBlock() => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _CodeView(
                        block: block,
                        onChanged: (text) => _updateBlock(
                          block.id,
                          (b) => (b as CodeBlock).copyWith(text: text),
                        ),
                        onMenu: (position) => _showBlockMenu(position, block),
                      ),
                    ),
                    DividerBlock() => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: GestureDetector(
                        onSecondaryTapUp: (d) =>
                            _showBlockMenu(d.globalPosition, block),
                        child: Divider(color: colors.border, height: 24),
                      ),
                    ),
                    TableBlock() => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _TableView(
                        block: block,
                        controllerFor: _cellControllerFor,
                        onMenu: (position) => _showBlockMenu(position, block),
                      ),
                    ),
                    ImageBlock() => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: _ImageView(
                        block: block,
                        onCaptionChanged: (caption) => _updateBlock(
                          block.id,
                          (b) => (b as ImageBlock).copyWith(caption: caption),
                        ),
                        onWidthChanged: widget.readOnly
                            ? null
                            : (fraction) => _updateBlock(
                                block.id,
                                (b) => (b as ImageBlock).copyWith(
                                  widthFraction: fraction,
                                  clearWidthFraction: fraction == null,
                                ),
                              ),
                        onMenu: (position) => _showBlockMenu(position, block),
                      ),
                    ),
                  },
                ),
              ),
            ),
          const SizedBox(height: 24),
          AbsorbPointer(
            absorbing: widget.readOnly,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _AddParagraph(
                onTap: () {
                  final block = ParagraphBlock(id: newId(), spans: const []);
                  _commit(
                    _document.copyWith(blocks: [..._document.blocks, block]),
                  );
                  WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _focusFor(block.id).requestFocus(),
                  );
                },
                color: colors.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Everything the toolbar does not carry: colour, highlight, font, spacing,
  /// images and export.
  Future<void> _showBlockMenu(Offset position, Block block) async {
    final colors = context.ds;
    final isParagraph = block is ParagraphBlock;

    DsMenuItem<VoidCallback> item(
      String label,
      VoidCallback action, {
      bool enabled = true,
    }) => DsMenuItem<VoidCallback>(
      value: action,
      height: kDsCompactMenuItemHeight,
      enabled: enabled,
      child: Text(
        label,
        style: uiTextStyle(
          size: 13,
          color: enabled ? colors.text : colors.muted,
        ),
      ),
    );

    final action = await showDsMenu<VoidCallback>(
      context: context,
      position: position,
      items: [
        if (isParagraph) ...[
          item('Bold', () => _toggle(block.id, EditingFormat.bold)),
          item('Italic', () => _toggle(block.id, EditingFormat.italic)),
          item(
            'Strikethrough',
            () => _toggle(block.id, EditingFormat.strikethrough),
          ),
          item('Underline', () => _toggle(block.id, EditingFormat.underline)),
          item('Link…', () => _setLink(block.id)),
          const DsMenuDivider(),
          PopupMenuItem<VoidCallback>(
            height: kDsMenuItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Swatches(
              label: 'Text',
              colors: kTextColors,
              onPick: (c) => _setColor(block.id, c, highlight: false),
            ),
          ),
          PopupMenuItem<VoidCallback>(
            height: kDsMenuItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Swatches(
              label: 'Highlight',
              colors: kHighlightColors,
              onPick: (c) => _setColor(block.id, c, highlight: true),
            ),
          ),
          const DsMenuDivider(),
          for (final font in kAvailableFonts)
            item(font, () => _setFont(block.id, font)),
          const DsMenuDivider(),
        ],
        item(
          'Align left',
          () => _updateBlock(
            block.id,
            (b) => b.copyWithCommon(align: BlockAlign.left),
          ),
        ),
        item(
          'Align centre',
          () => _updateBlock(
            block.id,
            (b) => b.copyWithCommon(align: BlockAlign.center),
          ),
        ),
        item(
          'Align right',
          () => _updateBlock(
            block.id,
            (b) => b.copyWithCommon(align: BlockAlign.right),
          ),
        ),
        const DsMenuDivider(),
        item(
          block.spaceBefore > 0 ? 'No space before' : 'Space before',
          () => _updateBlock(
            block.id,
            (b) => b.copyWithCommon(
              spaceBefore: b.spaceBefore > 0 ? 0 : DsSpace.blockBefore,
            ),
          ),
        ),
        if (block is ImageBlock) ...[
          const DsMenuDivider(),
          PopupMenuItem<VoidCallback>(
            height: kDsMenuItemHeight,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _ImageWidthPresets(
              current: block.widthFraction,
              onPick: (fraction) => _updateBlock(
                block.id,
                (b) => (b as ImageBlock).copyWith(
                  widthFraction: fraction,
                  clearWidthFraction: fraction == null,
                ),
              ),
            ),
          ),
        ],
        if (block is TextBlock) ...[
          const DsMenuDivider(),
          item(
            'Body text',
            () => _convertBlock(
              block.id,
              (b) => ParagraphBlock(
                id: b.id,
                spans: b.spans,
                align: b.align,
                spaceBefore: b.spaceBefore,
              ),
            ),
          ),
          item(
            'Bulleted list',
            () => _convertBlock(
              block.id,
              (b) => ListItemBlock(
                id: b.id,
                spans: b.spans,
                align: b.align,
                spaceBefore: b.spaceBefore,
              ),
            ),
          ),
          item(
            'Numbered list',
            () => _convertBlock(
              block.id,
              (b) => ListItemBlock(
                id: b.id,
                spans: b.spans,
                style: ListStyle.ordered,
                align: b.align,
                spaceBefore: b.spaceBefore,
              ),
            ),
          ),
          item(
            'Task',
            () => _convertBlock(
              block.id,
              (b) => ListItemBlock(
                id: b.id,
                spans: b.spans,
                checked: false,
                align: b.align,
                spaceBefore: b.spaceBefore,
              ),
            ),
          ),
          item(
            'Quote',
            () => _convertBlock(
              block.id,
              (b) => QuoteBlock(
                id: b.id,
                spans: b.spans,
                align: b.align,
                spaceBefore: b.spaceBefore,
              ),
            ),
          ),
          item(
            'Code block',
            () => _convertBlock(
              block.id,
              (b) => CodeBlock(
                id: b.id,
                text: b.plainText,
                align: b.align,
                spaceBefore: b.spaceBefore,
              ),
            ),
          ),
          if (block is ListItemBlock && block.depth < 8)
            item(
              'Indent',
              () => _updateBlock(
                block.id,
                (b) => (b as ListItemBlock).copyWith(depth: b.depth + 1),
              ),
            ),
          if (block is ListItemBlock && block.depth > 0)
            item(
              'Outdent',
              () => _updateBlock(
                block.id,
                (b) => (b as ListItemBlock).copyWith(depth: b.depth - 1),
              ),
            ),
        ],
        if (block is TableBlock) ...[
          const DsMenuDivider(),
          item('Add row', () => _addTableRow(block.id)),
          item('Add column', () => _addTableColumn(block.id)),
        ],
        const DsMenuDivider(),
        item(
          'Insert divider',
          () => _insertAfter(block.id, DividerBlock(id: newId())),
        ),
        item('Insert table', () => _insertTable(block.id)),
        if (isParagraph)
          item('Insert footnote', () => _insertFootnote(block.id)),
        item('Insert image…', () => _insertImage(block.id)),
        item('Insert image by URL…', () => _insertImageUrl(block.id)),
        const DsMenuDivider(),
        item('Export as .docx…', () => _export(DocumentFormat.docx)),
        item('Export as .odt…', () => _export(DocumentFormat.odt)),
        const DsMenuDivider(),
        item(
          block is ImageBlock ? 'Delete image' : 'Delete block',
          () => _deleteBlock(block.id),
        ),
      ],
    );

    action?.call();
  }
}

/// Reveals an ellipsis at a block's right edge while the pointer is over it.
/// The button opens the block menu without touching the text selection — it
/// is a GestureDetector, never a Material button, for the same reason
/// [DsButton] is one.
class _BlockHoverGrip extends StatefulWidget {
  const _BlockHoverGrip({
    required this.child,
    required this.onMenu,
    required this.enabled,
    this.peers = const [],
  });

  final Widget child;
  final void Function(Offset position) onMenu;
  final bool enabled;

  /// Collaborators whose caret is in this block. Shown whether or not the
  /// grip itself is enabled: a read-only view still wants to know who is
  /// working where.
  final List<PeerPresence> peers;

  @override
  State<_BlockHoverGrip> createState() => _BlockHoverGripState();
}

/// How far into the page margin the peer marker sits. The editor's own list
/// padding is 48, so this leaves the marker clear of the text without
/// reaching the pane edge.
const double _peerMarkerInset = 34;

class _BlockHoverGripState extends State<_BlockHoverGrip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return MouseRegion(
      onEnter: (_) {
        if (widget.enabled && !_hovered) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      child: Stack(
        // The peer marker sits out in the page margin, the way it does in the
        // editors this borrows from, so it never crowds the prose.
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (widget.peers.isNotEmpty)
            Positioned(
              left: -_peerMarkerInset,
              top: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.topLeft,
                    child: PresenceDots(
                      key: ValueKey(
                        'presence-in-block-${widget.peers.first.blockId}',
                      ),
                      peers: widget.peers,
                      maxVisible: 2,
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: DsPresence.blockMarkerWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: presenceColorFor(widget.peers.first.userId),
                        borderRadius: const BorderRadius.all(
                          Radius.circular(DsPresence.blockMarkerWidth),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.enabled && _hovered)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) => widget.onMenu(details.globalPosition),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: Container(
                      key: const Key('block-hover-grip'),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: colors.island,
                        border: Border.fromBorderSide(
                          BorderSide(color: colors.surfaceOutline),
                        ),
                        borderRadius: const BorderRadius.all(DsRadius.row),
                      ),
                      child: Icon(
                        Icons.more_horiz,
                        size: 14,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------- format transforms --

Format _withColor(Format format, String? color) =>
    format.copyWith(color: (_) => color);
Format _withHighlight(Format format, String? color) =>
    format.copyWith(highlight: (_) => color);
Format _withFont(Format format, String? font) =>
    format.copyWith(font: (_) => font);

final RegExp _autoformatPattern = RegExp(r'^(#{1,6} |[-*+] |\d+[.)] |> )');

Format _withHref(Format format, String? href) =>
    format.copyWith(href: (_) => href);

/// Splits a span list at character offsets, preserving each run's formatting.
List<TextSpanNode> _sliceSpans(List<TextSpanNode> spans, int start, int end) {
  final out = <TextSpanNode>[];
  var cursor = 0;
  for (final span in spans) {
    final spanStart = cursor;
    final spanEnd = cursor + span.text.length;
    cursor = spanEnd;

    final from = start.clamp(spanStart, spanEnd);
    final to = end.clamp(spanStart, spanEnd);
    if (to <= from) continue;
    out.add(
      span.copyWith(
        text: span.text.substring(from - spanStart, to - spanStart),
      ),
    );
  }
  return out;
}

// -------------------------------------------------------------- block views --

/// One editable text block — a paragraph or a heading. They differ only in
/// [style], so everything else here is shared.
class _TextBlockView extends StatelessWidget {
  const _TextBlockView({
    required this.block,
    required this.controller,
    required this.focusNode,
    required this.style,
    required this.onSplit,
    this.ordinal,
    this.onToggleChecked,
    required this.onMergeBack,
    required this.onMenu,
    required this.onPublish,
  });

  final TextBlock block;
  final RichTextController controller;
  final FocusNode focusNode;
  final TextStyle style;

  /// The number to draw beside an ordered list item.
  final int? ordinal;

  /// Set for a task item; toggles its checkbox.
  final VoidCallback? onToggleChecked;

  final VoidCallback onSplit;
  final bool Function() onMergeBack;
  final void Function(Offset position) onMenu;
  final VoidCallback onPublish;

  TextAlign get _align => switch (block.align) {
    BlockAlign.left => TextAlign.left,
    BlockAlign.center => TextAlign.center,
    BlockAlign.right => TextAlign.right,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return GestureDetector(
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: _decorate(
        context,
        Shortcuts(
          shortcuts: {
            const SingleActivator(LogicalKeyboardKey.enter):
                const _SplitIntent(),
            SingleActivator(
              LogicalKeyboardKey.keyS,
              meta: defaultTargetPlatform == TargetPlatform.macOS,
              control: defaultTargetPlatform != TargetPlatform.macOS,
            ): const _PublishIntent(),
            for (final entry in KeybindHashMap.instance.entries)
              entry.value.activator(defaultTargetPlatform): _FormatIntent(
                entry.key.toEditingFormat(),
              ),
          },
          child: Actions(
            actions: {
              _SplitIntent: CallbackAction<_SplitIntent>(
                onInvoke: (_) => onSplit(),
              ),
              _FormatIntent: CallbackAction<_FormatIntent>(
                onInvoke: (intent) => _toggleHere(intent.format),
              ),
              _PublishIntent: CallbackAction<_PublishIntent>(
                onInvoke: (_) => onPublish(),
              ),
            },
            child: Focus(
              onKeyEvent: (node, event) {
                final isBackspace =
                    event.logicalKey == LogicalKeyboardKey.backspace;
                final atStart =
                    controller.selection.isCollapsed &&
                    controller.selection.baseOffset == 0;
                if (event is KeyDownEvent && isBackspace && atStart) {
                  return onMergeBack()
                      ? KeyEventResult.handled
                      : KeyEventResult.ignored;
                }
                return KeyEventResult.ignored;
              },
              // The wash follows the caret, so it has to repaint when this
              // block gains or loses focus rather than only when the document
              // changes.
              child: ListenableBuilder(
                listenable: focusNode,
                builder: (context, child) => AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  curve: Curves.easeOut,
                  // Constant padding: only the colour changes with focus, so
                  // the text does not shift as it is clicked into.
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    // Fading to Colors.transparent would fade through
                    // transparent *black*, greying the block on the way in and
                    // out. Only the alpha should move, so the far end of the
                    // animation is this same colour at zero alpha.
                    color: focusNode.hasFocus
                        ? colors.editingBlock
                        : colors.editingBlock.withAlpha(0),
                    borderRadius: const BorderRadius.all(DsRadius.block),
                  ),
                  child: child,
                ),
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  maxLines: null,
                  textAlign: _align,
                  cursorColor: colors.text,
                  cursorWidth: 1.5,
                  style: style,
                  decoration: const InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 2),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps the field in whatever the block kind puts around it: a list
  /// marker and indent, or a quote's rule. A paragraph or heading gets
  /// nothing, so those are laid out exactly as they were before.
  Widget _decorate(BuildContext context, Widget field) {
    final colors = context.ds;
    final b = block;

    if (b is QuoteBlock) {
      return Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colors.border, width: 3)),
        ),
        child: field,
      );
    }

    if (b is FootnoteBlock) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 3, right: 6),
            child: Text(
              '[${b.label}]',
              style: editorTextStyle(size: 12, weight: 500, color: colors.link),
            ),
          ),
          Expanded(child: field),
        ],
      );
    }

    if (b is ListItemBlock) {
      return Padding(
        padding: EdgeInsets.only(left: 20.0 * b.depth),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 22, child: _marker(colors, b)),
            Expanded(child: field),
          ],
        ),
      );
    }

    return field;
  }

  Widget _marker(DsColors colors, ListItemBlock b) {
    if (b.checked != null) {
      return GestureDetector(
        onTap: onToggleChecked,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Icon(
            b.checked! ? Icons.check_box : Icons.check_box_outline_blank,
            size: 15,
            color: b.checked! ? colors.muted : colors.border,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text(
        b.style == ListStyle.ordered ? '${ordinal ?? 1}.' : '•',
        style: editorTextStyle(size: 15, height: 1.6, color: colors.muted),
      ),
    );
  }

  void _toggleHere(EditingFormat format) {
    final selection = controller.selection;
    controller.toggleFormat(format, selection);
  }
}

class _SplitIntent extends Intent {
  const _SplitIntent();
}

class _PublishIntent extends Intent {
  const _PublishIntent();
}

class _FormatIntent extends Intent {
  const _FormatIntent(this.format);

  final EditingFormat format;
}

/// Image decode widths are rounded up to this many logical pixels so that
/// resizing an image, or nudging the window, reuses the cached decode.
const double _kDecodeQuantum = 64;

class _ImageView extends ConsumerStatefulWidget {
  const _ImageView({
    required this.block,
    required this.onCaptionChanged,
    required this.onMenu,
    this.onWidthChanged,
  });

  final ImageBlock block;
  final ValueChanged<String> onCaptionChanged;
  final ValueChanged<double?>? onWidthChanged;
  final void Function(Offset position) onMenu;

  @override
  ConsumerState<_ImageView> createState() => _ImageViewState();
}

class _ImageViewState extends ConsumerState<_ImageView> {
  // One controller for the life of this view. A fresh controller per build
  // would reset the caret to the start on every keystroke (the editor rebuilds
  // as the caption commits), so typed characters would prepend themselves.
  late final TextEditingController _caption = TextEditingController(
    text: widget.block.caption,
  );
  final FocusNode _captionFocus = FocusNode();
  bool _hovered = false;
  double _dragStartFraction = 1.0;
  double _dragStartX = 0;

  @override
  void didUpdateWidget(_ImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Outside changes — undo, a merge — reach the field only while it is not
    // being edited; otherwise the caret would jump mid-keystroke.
    if (!_captionFocus.hasFocus && _caption.text != widget.block.caption) {
      _caption.value = TextEditingValue(
        text: widget.block.caption,
        selection: TextSelection.collapsed(offset: widget.block.caption.length),
      );
    }
  }

  @override
  void dispose() {
    _caption.dispose();
    _captionFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final block = widget.block;
    final session = ref.watch(kbSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final file = block.isExternal
        ? null
        : File(session.kb.assetPathFor(block.assetId));
    final alignment = switch (block.align) {
      BlockAlign.left => CrossAxisAlignment.start,
      BlockAlign.center => CrossAxisAlignment.center,
      BlockAlign.right => CrossAxisAlignment.end,
    };
    final align = switch (block.align) {
      BlockAlign.left => Alignment.centerLeft,
      BlockAlign.center => Alignment.center,
      BlockAlign.right => Alignment.centerRight,
    };
    final canResize = widget.onWidthChanged != null;

    return GestureDetector(
      onSecondaryTapUp: (details) => widget.onMenu(details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final fraction = block.effectiveFraction.clamp(
              kImageMinFraction,
              kImageMaxFraction,
            );
            final targetWidth = (maxWidth * fraction).clamp(
              kImageMinWidth,
              maxWidth,
            );
            final pixelRatio = MediaQuery.of(context).devicePixelRatio;
            // Decode once at the widest size this image could ever be shown
            // at, quantized so ordinary layout jitter doesn't change it
            // either. Deriving it from targetWidth instead would hand the
            // image a new provider on every drag frame: each one misses the
            // image cache and decodes asynchronously, so the image blanks and
            // flickers while resizing and only settles once a width has been
            // visited before.
            final decodeWidth =
                (((maxWidth * kImageMaxFraction) / _kDecodeQuantum).ceil() *
                        _kDecodeQuantum)
                    .toDouble();
            final cacheWidth = (decodeWidth * pixelRatio).round();

            Widget imageChild;
            if (block.isExternal) {
              imageChild = Image.network(
                block.url!,
                fit: BoxFit.contain,
                width: targetWidth,
                gaplessPlayback: true,
                // A URL can fail for reasons the document knows nothing
                // about, so it must not take the editor down with it.
                errorBuilder: (context, _, _) => Container(
                  height: 80,
                  width: targetWidth,
                  alignment: Alignment.center,
                  color: colors.selection,
                  child: Text(
                    'Image unavailable',
                    style: uiTextStyle(size: 13, color: colors.muted),
                  ),
                ),
              );
            } else if (file!.existsSync()) {
              imageChild = Image.file(
                file,
                fit: BoxFit.contain,
                width: targetWidth,
                cacheWidth: cacheWidth,
                filterQuality: FilterQuality.medium,
                // Hold the last decoded frame if the provider ever does
                // change, rather than flashing empty space.
                gaplessPlayback: true,
                errorBuilder: (context, _, _) => Container(
                  height: 80,
                  width: targetWidth,
                  alignment: Alignment.center,
                  color: colors.selection,
                  child: Text(
                    'Image missing',
                    style: uiTextStyle(size: 12, color: colors.muted),
                  ),
                ),
              );
            } else {
              imageChild = Container(
                height: 80,
                width: targetWidth,
                alignment: Alignment.center,
                color: colors.selection,
                child: Text(
                  'Image missing',
                  style: uiTextStyle(size: 12, color: colors.muted),
                ),
              );
            }

            final imageStack = Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.all(DsRadius.control),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: kImageMaxHeight,
                      maxWidth: targetWidth,
                    ),
                    child: Align(
                      alignment: Alignment.center,
                      widthFactor: 1,
                      heightFactor: 1,
                      child: imageChild,
                    ),
                  ),
                ),
                if (canResize)
                  Positioned(
                    right: 4,
                    bottom: 4,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.resizeLeftRight,
                      onEnter: (_) => setState(() => _hovered = true),
                      onExit: (_) => setState(() => _hovered = false),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onPanStart: (details) {
                          _dragStartFraction = block.effectiveFraction;
                          _dragStartX = details.globalPosition.dx;
                        },
                        onPanUpdate: (details) {
                          final delta = details.globalPosition.dx - _dragStartX;
                          final next = (_dragStartFraction + delta / maxWidth)
                              .clamp(kImageMinFraction, kImageMaxFraction)
                              .toDouble();
                          final rounded = double.parse(next.toStringAsFixed(2));
                          final normalized = rounded >= 0.99 ? null : rounded;
                          // Avoid noisy commits when the value hasn't changed.
                          final current = block.widthFraction;
                          final curRounded = current == null
                              ? null
                              : double.parse(current.toStringAsFixed(2));
                          final normRounded = normalized == null
                              ? null
                              : double.parse(normalized.toStringAsFixed(2));
                          if (curRounded != normRounded) {
                            widget.onWidthChanged!(normalized);
                          }
                        },
                        child: AnimatedOpacity(
                          opacity: _hovered ? 1 : 0.7,
                          duration: const Duration(milliseconds: 120),
                          child: Container(
                            width: 28,
                            height: 20,
                            decoration: BoxDecoration(
                              color: colors.island.withAlpha(230),
                              border: Border.all(color: colors.border),
                              borderRadius: const BorderRadius.all(
                                DsRadius.control,
                              ),
                            ),
                            child: Icon(
                              Icons.open_in_full,
                              size: 12,
                              color: colors.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );

            return Column(
              crossAxisAlignment: alignment,
              children: [
                Align(alignment: align, child: imageStack),
                const SizedBox(height: 6),
                Align(
                  alignment: align,
                  child: SizedBox(
                    width: targetWidth,
                    child: TextField(
                      controller: _caption,
                      focusNode: _captionFocus,
                      onChanged: widget.onCaptionChanged,
                      textAlign: switch (block.align) {
                        BlockAlign.left => TextAlign.left,
                        BlockAlign.center => TextAlign.center,
                        BlockAlign.right => TextAlign.right,
                      },
                      style: editorTextStyle(
                        size: 12,
                        italic: true,
                        color: colors.muted,
                      ),
                      cursorColor: colors.text,
                      cursorWidth: 1.5,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Caption',
                        hintStyle: editorTextStyle(
                          size: 12,
                          italic: true,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ),
                ),
                if (canResize)
                  Align(
                    alignment: align,
                    child: SizedBox(
                      width: targetWidth,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '${(fraction * 100).round()}% · drag handle to resize',
                          style: uiTextStyle(size: 10, color: colors.muted),
                          textAlign: switch (block.align) {
                            BlockAlign.left => TextAlign.left,
                            BlockAlign.center => TextAlign.center,
                            BlockAlign.right => TextAlign.right,
                          },
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class DocumentTitleField extends ConsumerStatefulWidget {
  const DocumentTitleField({
    super.key,
    required this.title,
    required this.onRename,
  });

  final String title;
  final Future<String?> Function(String title) onRename;

  @override
  ConsumerState<DocumentTitleField> createState() => _DocumentTitleFieldState();
}

class _DocumentTitleFieldState extends ConsumerState<DocumentTitleField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.title,
  );
  late final FocusNode _focus = FocusNode()..addListener(_onFocusChanged);
  late String _committedTitle = widget.title;
  bool _renaming = false;
  Future<bool>? _activeRename;
  Future<void>? _activeSave;

  @override
  void didUpdateWidget(DocumentTitleField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.title != _committedTitle) {
      _committedTitle = widget.title;
      _setText(widget.title);
    }
  }

  void _onFocusChanged() {
    if (!_focus.hasFocus) unawaited(_commitRename());
  }

  void _setText(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Future<void> saveAndPublish() => _saveAndPublish();

  Future<void> _saveAndPublish() async {
    final active = _activeSave;
    if (active != null) return active;

    final future = _performSaveAndPublish();
    _activeSave = future;
    try {
      await future;
    } finally {
      if (identical(_activeSave, future)) {
        _activeSave = null;
      }
    }
  }

  Future<void> _performSaveAndPublish() async {
    final renameSuccess = await _commitRename();
    if (!renameSuccess || !mounted) return;
    await publishOpenDocumentFromShortcut(context, ref);
  }

  Future<bool> _commitRename() async {
    final active = _activeRename;
    if (active != null) return active;

    final future = _performCommitRename();
    _activeRename = future;
    try {
      return await future;
    } finally {
      if (identical(_activeRename, future)) {
        _activeRename = null;
      }
    }
  }

  Future<bool> _performCommitRename() async {
    final requested = _controller.text.trim();
    if (requested.isEmpty) {
      _setText(_committedTitle);
      return true;
    }
    if (requested == _committedTitle) return true;

    setState(() => _renaming = true);
    try {
      final canonical = await widget.onRename(requested);
      if (!mounted) return canonical != null;

      if (canonical == null) {
        _setText(_committedTitle);
        return false;
      } else {
        _committedTitle = canonical;
        _setText(canonical);
        return true;
      }
    } finally {
      if (mounted) setState(() => _renaming = false);
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_saveAndPublish()),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_saveAndPublish()),
      },
      child: TextField(
        controller: _controller,
        focusNode: _focus,
        readOnly: _renaming,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) async {
          await _commitRename();
          _focus.unfocus();
        },
        onTapOutside: (_) => _focus.unfocus(),
        maxLines: 1,
        style: editorTextStyle(size: 24, weight: 600, color: colors.text),
        cursorColor: colors.text,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: 'Untitled',
          hintStyle: editorTextStyle(
            size: 24,
            weight: 600,
            color: colors.muted,
          ),
        ),
      ),
    );
  }
}

/// A table. Each cell is an ordinary rich-text field, so formatting inside one
/// works exactly as it does in a paragraph.
class _TableView extends StatelessWidget {
  const _TableView({
    required this.block,
    required this.controllerFor,
    required this.onMenu,
  });

  final TableBlock block;
  final RichTextController Function(TableBlock, int, int) controllerFor;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final columns = block.columnCount;
    if (columns == 0) return const SizedBox.shrink();

    return GestureDetector(
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: colors.border),
          borderRadius: const BorderRadius.all(DsRadius.control),
        ),
        child: Column(
          children: [
            for (var r = 0; r < block.rows.length; r++)
              Container(
                decoration: BoxDecoration(
                  border: r == 0
                      ? Border(bottom: BorderSide(color: colors.border))
                      : null,
                  color: r == 0 ? colors.selection : null,
                ),
                // Stretch needs a bounded height, and a row's height is its
                // tallest cell — which is exactly what IntrinsicHeight
                // measures. It is what makes the column rules run full height.
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < columns; c++)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              border: c == 0
                                  ? null
                                  : Border(
                                      left: BorderSide(color: colors.border),
                                    ),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            child: c < block.rows[r].length
                                ? TextField(
                                    controller: controllerFor(block, r, c),
                                    maxLines: null,
                                    textAlign: switch (block.alignOf(c)) {
                                      BlockAlign.left => TextAlign.left,
                                      BlockAlign.center => TextAlign.center,
                                      BlockAlign.right => TextAlign.right,
                                    },
                                    cursorColor: colors.text,
                                    cursorWidth: 1.5,
                                    style: editorTextStyle(
                                      size: 14,
                                      height: 1.5,
                                      weight: r == 0 ? 600 : 400,
                                      color: colors.text,
                                    ),
                                    decoration: const InputDecoration(
                                      isCollapsed: true,
                                      border: InputBorder.none,
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A fenced code block. Plain text on a tinted panel — no rich formatting,
/// because none of it means anything inside code.
class _CodeView extends StatelessWidget {
  const _CodeView({
    required this.block,
    required this.onChanged,
    required this.onMenu,
  });

  final CodeBlock block;
  final ValueChanged<String> onChanged;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return GestureDetector(
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: colors.selection,
          borderRadius: const BorderRadius.all(DsRadius.control),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (block.language != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  block.language!,
                  style: editorTextStyle(size: 11, color: colors.muted),
                ),
              ),
            TextField(
              controller: TextEditingController(
                text: block.text,
              )..selection = TextSelection.collapsed(offset: block.text.length),
              onChanged: onChanged,
              maxLines: null,
              cursorColor: colors.text,
              cursorWidth: 1.5,
              style: editorTextStyle(
                size: 13,
                height: 1.5,
                color: colors.text,
              ).copyWith(fontFamily: 'Courier New'),
              decoration: const InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddParagraph extends StatelessWidget {
  const _AddParagraph({required this.onTap, required this.color});

  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: 28,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('+', style: uiTextStyle(size: 15, color: color)),
          ),
        ),
      ),
    );
  }
}

class _Swatches extends StatelessWidget {
  const _Swatches({
    required this.label,
    required this.colors,
    required this.onPick,
  });

  final String label;
  final List<String> colors;
  final void Function(String? color) onPick;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(label, style: uiTextStyle(size: 13, color: ds.text)),
        ),
        for (final hex in colors)
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              onPick(hex);
            },
            child: Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(
                color: parseColor(hex),
                shape: BoxShape.circle,
                border: Border.all(color: ds.border),
              ),
            ),
          ),
        GestureDetector(
          onTap: () {
            Navigator.of(context).pop();
            onPick(null);
          },
          child: Text('none', style: uiTextStyle(size: 11, color: ds.muted)),
        ),
      ],
    );
  }
}

class _ImageWidthPresets extends StatelessWidget {
  const _ImageWidthPresets({required this.current, required this.onPick});

  final double? current;
  final void Function(double? fraction) onPick;

  @override
  Widget build(BuildContext context) {
    final ds = context.ds;
    const presets = [(0.25, 'S'), (0.5, 'M'), (0.75, 'L'), (null, 'Full')];
    bool isSelected(double? preset) {
      if (preset == null) return current == null;
      if (current == null) return false;
      return (current! - preset).abs() < 0.01;
    }

    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text('Width', style: uiTextStyle(size: 13, color: ds.text)),
        ),
        for (final (value, label) in presets)
          GestureDetector(
            onTap: () {
              Navigator.of(context).pop();
              onPick(value);
            },
            child: Container(
              width: 32,
              height: 22,
              margin: const EdgeInsets.only(right: 6),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected(value) ? ds.selection : Colors.transparent,
                border: Border.all(
                  color: isSelected(value) ? ds.text : ds.border,
                ),
                borderRadius: const BorderRadius.all(DsRadius.control),
              ),
              child: Text(
                label,
                style: uiTextStyle(
                  size: 11,
                  weight: isSelected(value) ? 600 : 400,
                  color: ds.text,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
