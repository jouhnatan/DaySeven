/// The editing surface.
///
/// Content is a column of blocks; each paragraph is its own block, so pressing
/// Return starts a new one and Backspace at the head of a block merges it into
/// the one above. Formatting comes from three places: the toolbar in the bottom
/// bar, keyboard shortcuts, and a context menu on the block for the rest —
/// colour, highlight, font, spacing, images and export.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/documents/documents.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/block_text_style.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';

class EditorScreen extends ConsumerWidget {
  const EditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(documentControllerProvider);

    if (open == null) {
      return Center(
        child: Text(
          'Open a document from the Knowledge Base.',
          style: aleo(size: 13, color: colors.muted),
        ),
      );
    }

    return DocumentEditor(key: ValueKey(open.relativePath), open: open);
  }
}

class DocumentEditor extends ConsumerStatefulWidget {
  const DocumentEditor({super.key, required this.open});

  final OpenDocument open;

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

  FocusNode _focusFor(String blockId) => _focusNodes.putIfAbsent(blockId, () {
    final node = FocusNode();
    node.addListener(() => _publishFocus(blockId));
    return node;
  });

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

      final range = TextRange(start: selection.start, end: selection.end);
      _editingFocus.publish(
        EditingFocus(
          blockId: blockId,
          hasSelection: has,
          bold: has && controller.rangeSatisfies(range, (f) => f.bold),
          italic: has && controller.rangeSatisfies(range, (f) => f.italic),
          strikethrough:
              has && controller.rangeSatisfies(range, (f) => f.strikethrough),
          underline:
              has && controller.rangeSatisfies(range, (f) => f.underline),
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

    final selection =
        controller.selection.isValid && !controller.selection.isCollapsed
        ? controller.selection
        : _lastSelection[focus.blockId];
    if (selection == null || selection.isCollapsed) return;

    final range = TextRange(start: selection.start, end: selection.end);
    final (apply, test) = switch (format) {
      EditingFormat.bold => (_withBold, (Format f) => f.bold),
      EditingFormat.italic => (_withItalic, (Format f) => f.italic),
      EditingFormat.strikethrough => (
        _withStrike,
        (Format f) => f.strikethrough,
      ),
      EditingFormat.underline => (_withUnderline, (Format f) => f.underline),
    };

    final already = controller.rangeSatisfies(range, test);
    controller.applyToRange(range, (f) => apply(f, !already));

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

  void _commit(BlockDocument document, {bool rebuild = true}) {
    _document = document;
    ref.read(documentControllerProvider.notifier).edit(document);
    if (rebuild && mounted) setState(() {});
  }

  void _onParagraphChanged(String blockId) {
    final controller = _controllers[blockId];
    if (controller == null) return;

    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _document.blocks[index];
    if (block is! TextBlock) return;

    final spans = controller.toSpans();
    final blocks = [..._document.blocks];
    blocks[index] = block.withSpans(spans);
    // No rebuild: the field is already showing this text.
    _commit(_document.copyWith(blocks: blocks), rebuild: false);
  }

  // --------------------------------------------------------- block editing --

  void _splitBlock(String blockId) {
    final index = _document.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final controller = _controllers[blockId]!;
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
      if (c != null) c.selection = const TextSelection.collapsed(offset: 0);
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

  Future<void> _insertImage(String afterBlockId) async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    const typeGroup = XTypeGroup(
      label: 'Images',
      extensions: ['png', 'jpg', 'jpeg', 'gif', 'webp', 'tiff'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    final assetId = await session.kb.importAsset(File(file.path));
    final index = _document.blocks.indexWhere((b) => b.id == afterBlockId);
    final blocks = [..._document.blocks]
      ..insert(index + 1, ImageBlock(id: newId(), assetId: assetId));
    _commit(_document.copyWith(blocks: blocks));
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

  void _toggle(
    String blockId,
    Format Function(Format, bool) apply,
    bool Function(Format) test,
  ) {
    final controller = _controllers[blockId];
    if (controller == null) return;
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;

    final range = TextRange(start: selection.start, end: selection.end);
    final already = controller.rangeSatisfies(range, test);
    controller.applyToRange(range, (f) => apply(f, !already));
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

    return Focus(
      onKeyEvent: (node, event) => KeyEventResult.ignored,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(48, 40, 48, 120),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _TitleField(
              title: _document.title,
              onChanged: (title) =>
                  _commit(_document.copyWith(title: title), rebuild: false),
            ),
          ),
          const SizedBox(height: 20),
          for (final block in _document.blocks)
            Padding(
              padding: EdgeInsets.only(top: block.spaceBefore),
              child: switch (block) {
                // Headings differ from paragraphs only in the style the text
                // sits on, so both use the same view and the same controller.
                final TextBlock t => _TextBlockView(
                  block: t,
                  controller: _controllerFor(t),
                  focusNode: _focusFor(t.id),
                  style: t is HeadingBlock
                      ? headingStyle(t.level, colors.text)
                      : aleo(size: 15, height: 1.6, color: colors.text),
                  onSplit: () => _splitBlock(t.id),
                  onMergeBack: () => _mergeIntoPrevious(t.id),
                  onMenu: (position) => _showBlockMenu(position, t),
                ),
                ImageBlock() => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: _ImageView(
                    block: block,
                    onCaptionChanged: (caption) => _updateBlock(
                      block.id,
                      (b) => (b as ImageBlock).copyWith(caption: caption),
                    ),
                    onMenu: (position) => _showBlockMenu(position, block),
                  ),
                ),
              },
            ),
          const SizedBox(height: 24),
          Padding(
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
        ],
      ),
    );
  }

  /// Sends the document upstream. What that means depends on this account's
  /// standing: the owner commits a revision, everyone else proposes one.
  Future<void> _sync() async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final outcome = await ref
          .read(sharingControllerProvider)
          .syncOpenDocument();
      messenger?.showSnackBar(
        SnackBar(
          content: Text(switch (outcome) {
            SyncOutcome.committed => 'Saved as a new revision.',
            SyncOutcome.proposed => 'Sent for review.',
          }),
        ),
      );
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  /// Everything the toolbar does not carry: colour, highlight, font, spacing,
  /// images and export.
  Future<void> _showBlockMenu(Offset position, Block block) async {
    final colors = context.ds;
    final isParagraph = block is ParagraphBlock;
    final syncLabel = switch (ref.read(kbRoleProvider).valueOrNull) {
      KbRole.owner => 'Sync document',
      KbRole.editor => 'Propose changes',
      _ => null,
    };

    PopupMenuItem<VoidCallback> item(
      String label,
      VoidCallback action, {
      bool enabled = true,
    }) => PopupMenuItem<VoidCallback>(
      value: action,
      height: 32,
      enabled: enabled,
      child: Text(
        label,
        style: aleo(size: 13, color: enabled ? colors.text : colors.muted),
      ),
    );

    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.control),
        side: BorderSide(color: colors.border),
      ),
      items: [
        if (isParagraph) ...[
          item('Bold', () => _toggle(block.id, _withBold, (f) => f.bold)),
          item('Italic', () => _toggle(block.id, _withItalic, (f) => f.italic)),
          item(
            'Strikethrough',
            () => _toggle(block.id, _withStrike, (f) => f.strikethrough),
          ),
          item(
            'Underline',
            () => _toggle(block.id, _withUnderline, (f) => f.underline),
          ),
          const PopupMenuDivider(height: 1),
          PopupMenuItem<VoidCallback>(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Swatches(
              label: 'Text',
              colors: kTextColors,
              onPick: (c) => _setColor(block.id, c, highlight: false),
            ),
          ),
          PopupMenuItem<VoidCallback>(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _Swatches(
              label: 'Highlight',
              colors: kHighlightColors,
              onPick: (c) => _setColor(block.id, c, highlight: true),
            ),
          ),
          const PopupMenuDivider(height: 1),
          for (final font in kAvailableFonts)
            item(font, () => _setFont(block.id, font)),
          const PopupMenuDivider(height: 1),
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
        const PopupMenuDivider(height: 1),
        item(
          block.spaceBefore > 0 ? 'No space before' : 'Space before',
          () => _updateBlock(
            block.id,
            (b) => b.copyWithCommon(spaceBefore: b.spaceBefore > 0 ? 0 : 16),
          ),
        ),
        const PopupMenuDivider(height: 1),
        item('Insert image…', () => _insertImage(block.id)),
        const PopupMenuDivider(height: 1),
        item('Export as .docx…', () => _export(DocumentFormat.docx)),
        item('Export as .odt…', () => _export(DocumentFormat.odt)),
        if (syncLabel != null) ...[
          const PopupMenuDivider(height: 1),
          item(syncLabel, _sync),
        ],
      ],
    );

    action?.call();
  }
}

// -------------------------------------------------------- format transforms --

Format _withBold(Format f, bool on) => TextSpanNode(
  text: f.text,
  bold: on,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
);

Format _withItalic(Format f, bool on) => TextSpanNode(
  text: f.text,
  bold: f.bold,
  italic: on,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
);

Format _withStrike(Format f, bool on) => TextSpanNode(
  text: f.text,
  bold: f.bold,
  italic: f.italic,
  strikethrough: on,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
);

Format _withUnderline(Format f, bool on) => TextSpanNode(
  text: f.text,
  bold: f.bold,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: on,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
);

Format _withColor(Format f, String? color) => TextSpanNode(
  text: f.text,
  bold: f.bold,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: color,
  highlight: f.highlight,
  font: f.font,
);

Format _withHighlight(Format f, String? color) => TextSpanNode(
  text: f.text,
  bold: f.bold,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: f.color,
  highlight: color,
  font: f.font,
);

Format _withFont(Format f, String? font) => TextSpanNode(
  text: f.text,
  bold: f.bold,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: font,
);

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
    required this.onMergeBack,
    required this.onMenu,
  });

  final TextBlock block;
  final RichTextController controller;
  final FocusNode focusNode;
  final TextStyle style;
  final VoidCallback onSplit;
  final bool Function() onMergeBack;
  final void Function(Offset position) onMenu;

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
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): _SplitIntent(),
          SingleActivator(LogicalKeyboardKey.keyB, meta: true): _BoldIntent(),
          SingleActivator(LogicalKeyboardKey.keyB, control: true):
              _BoldIntent(),
          SingleActivator(LogicalKeyboardKey.keyI, meta: true): _ItalicIntent(),
          SingleActivator(LogicalKeyboardKey.keyI, control: true):
              _ItalicIntent(),
          SingleActivator(LogicalKeyboardKey.keyU, meta: true):
              _UnderlineIntent(),
          SingleActivator(LogicalKeyboardKey.keyU, control: true):
              _UnderlineIntent(),
          SingleActivator(LogicalKeyboardKey.keyX, meta: true, shift: true):
              _StrikeIntent(),
          SingleActivator(LogicalKeyboardKey.keyX, control: true, shift: true):
              _StrikeIntent(),
        },
        child: Actions(
          actions: {
            _SplitIntent: CallbackAction<_SplitIntent>(
              onInvoke: (_) => onSplit(),
            ),
            _BoldIntent: CallbackAction<_BoldIntent>(
              onInvoke: (_) => _toggleHere(_withBold, (f) => f.bold),
            ),
            _ItalicIntent: CallbackAction<_ItalicIntent>(
              onInvoke: (_) => _toggleHere(_withItalic, (f) => f.italic),
            ),
            _UnderlineIntent: CallbackAction<_UnderlineIntent>(
              onInvoke: (_) => _toggleHere(_withUnderline, (f) => f.underline),
            ),
            _StrikeIntent: CallbackAction<_StrikeIntent>(
              onInvoke: (_) => _toggleHere(_withStrike, (f) => f.strikethrough),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    );
  }

  void _toggleHere(
    Format Function(Format, bool) apply,
    bool Function(Format) test,
  ) {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final range = TextRange(start: selection.start, end: selection.end);
    final already = controller.rangeSatisfies(range, test);
    controller.applyToRange(range, (f) => apply(f, !already));
  }
}

class _SplitIntent extends Intent {
  const _SplitIntent();
}

class _BoldIntent extends Intent {
  const _BoldIntent();
}

class _ItalicIntent extends Intent {
  const _ItalicIntent();
}

class _UnderlineIntent extends Intent {
  const _UnderlineIntent();
}

class _StrikeIntent extends Intent {
  const _StrikeIntent();
}

class _ImageView extends ConsumerWidget {
  const _ImageView({
    required this.block,
    required this.onCaptionChanged,
    required this.onMenu,
  });

  final ImageBlock block;
  final ValueChanged<String> onCaptionChanged;
  final void Function(Offset position) onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final session = ref.watch(kbSessionProvider);
    if (session == null) return const SizedBox.shrink();

    final file = File(session.kb.assetPathFor(block.assetId));
    final alignment = switch (block.align) {
      BlockAlign.left => CrossAxisAlignment.start,
      BlockAlign.center => CrossAxisAlignment.center,
      BlockAlign.right => CrossAxisAlignment.end,
    };

    return GestureDetector(
      onSecondaryTapUp: (details) => onMenu(details.globalPosition),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.all(DsRadius.control),
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.contain)
                  : Container(
                      height: 80,
                      alignment: Alignment.center,
                      color: colors.selection,
                      child: Text(
                        'Image missing',
                        style: aleo(size: 12, color: colors.muted),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: TextEditingController(text: block.caption),
              onChanged: onCaptionChanged,
              textAlign: switch (block.align) {
                BlockAlign.left => TextAlign.left,
                BlockAlign.center => TextAlign.center,
                BlockAlign.right => TextAlign.right,
              },
              style: aleo(size: 12, italic: true, color: colors.muted),
              cursorColor: colors.text,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Caption',
                hintStyle: aleo(size: 12, italic: true, color: colors.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TitleField extends StatefulWidget {
  const _TitleField({required this.title, required this.onChanged});

  final String title;
  final ValueChanged<String> onChanged;

  @override
  State<_TitleField> createState() => _TitleFieldState();
}

class _TitleFieldState extends State<_TitleField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.title,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      maxLines: 1,
      style: aleo(size: 24, weight: 600, color: colors.text),
      cursorColor: colors.text,
      cursorWidth: 1.5,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: 'Untitled',
        hintStyle: aleo(size: 24, weight: 600, color: colors.muted),
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
            child: Text('+', style: aleo(size: 15, color: color)),
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
          child: Text(label, style: aleo(size: 13, color: ds.text)),
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
          child: Text('none', style: aleo(size: 11, color: ds.muted)),
        ),
      ],
    );
  }
}
