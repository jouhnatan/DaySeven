/// The review interface.
///
/// The current local file on the left, the proposed revision on the right, with
/// three actions and no others:
///   Approve — three-way merge, then a new revision.
///   Reject  — mark rejected; the file is not touched.
///   Return  — close the diff and leave the proposal pending.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/features/review/domain/merge.dart';
import 'package:dayseven/shared/blocks/revision.dart';
import 'package:dayseven/features/review/data/proposals.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/features/review/data/change_set_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/block_text_style.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/error_box.dart';

Route<void> diffRoute(ChangeSet proposal) => MaterialPageRoute<void>(
  builder: (_) => DiffScreen(proposal: proposal),
  fullscreenDialog: true,
);

class DiffScreen extends ConsumerStatefulWidget {
  const DiffScreen({super.key, required this.proposal});

  final ChangeSet proposal;

  @override
  ConsumerState<DiffScreen> createState() => _DiffScreenState();
}

class _DiffScreenState extends ConsumerState<DiffScreen> {
  bool _working = false;
  bool _loading = true;
  String? _error;
  BlockDocument? _current;
  String? _currentRevisionId;
  MergeResult? _merge;
  final Map<String, bool> _conflictChoices = {};
  bool? _titleChoice;
  final _reviewNote = TextEditingController();

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _reviewNote.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    try {
      final documents = ref.read(documentRepositoryProvider);
      final empty = BlockDocument(
        id: widget.proposal.targetDocumentId,
        title: '',
        blocks: const [],
      );
      if (widget.proposal.operation == ChangeSetOperation.create) {
        _current = empty;
        _merge = MergeResult(
          document: widget.proposal.content,
          conflictedBlockIds: const [],
        );
      } else {
        final baseId = widget.proposal.baseRevisionId;
        if (baseId == null) {
          throw const SyncException('The proposal has no base revision.');
        }
        final base = await documents.revision(baseId);
        if (base == null) {
          throw const SyncException(
            'The revision this was written against is gone.',
          );
        }
        _currentRevisionId = await documents.currentRevisionId(
          widget.proposal.targetDocumentId,
        );
        final currentRevision = _currentRevisionId == null
            ? null
            : await documents.revision(_currentRevisionId!);
        _current = currentRevision?.content ?? base.content;
        _merge = widget.proposal.operation == ChangeSetOperation.delete
            ? MergeResult(document: _current!, conflictedBlockIds: const [])
            : threeWayMerge(
                base: base.content,
                local: _current!,
                proposed: widget.proposal.content,
              );
      }
    } catch (error) {
      _error = describeError(error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Returning leaves the proposal exactly as it was found.
  void _return() => Navigator.of(context).pop();

  Future<void> _reject() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref
          .read(changeSetRepositoryProvider)
          .reject(widget.proposal.id, reviewNote: _reviewNote.text);
      ref.read(pendingProposalsProvider.notifier).remove(widget.proposal.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() {
        _error = describeError(error);
        _working = false;
      });
    }
  }

  Future<void> _approve() async {
    final merge = _resolvedMerge();
    if (merge == null) return;

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      await ref
          .read(changeSetRepositoryProvider)
          .approve(
            changeSetId: widget.proposal.id,
            merged: merge,
            expectedCurrentRevisionId: _currentRevisionId,
            reviewNote: _reviewNote.text,
          );

      final open = ref.read(documentControllerProvider);
      final session = ref.read(kbSessionProvider);
      if (open?.document.id == widget.proposal.targetDocumentId &&
          session != null &&
          widget.proposal.operation != ChangeSetOperation.delete) {
        await session.kb.writeDocument(open!.relativePath, merge);
        session.index.upsert(open.relativePath, merge);
        await ref
            .read(documentControllerProvider.notifier)
            .open(open.relativePath);
      }

      ref.read(pendingProposalsProvider.notifier).remove(widget.proposal.id);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() {
        _error = describeError(error);
        _working = false;
      });
    }
  }

  BlockDocument? _resolvedMerge() {
    final merge = _merge;
    final current = _current;
    if (merge == null || current == null) return null;
    if (merge.titleConflict && _titleChoice == null) return null;
    if (merge.conflictedBlockIds.any(
      (id) => !_conflictChoices.containsKey(id),
    )) {
      return null;
    }

    final currentById = {for (final block in current.blocks) block.id: block};
    final blocks = [...merge.document.blocks];
    for (final id in merge.conflictedBlockIds) {
      if (_conflictChoices[id] == true) continue;
      final at = blocks.indexWhere((block) => block.id == id);
      final replacement = currentById[id];
      if (at >= 0 && replacement != null) {
        blocks[at] = replacement;
      } else if (at >= 0) {
        blocks.removeAt(at);
      } else if (replacement != null) {
        blocks.add(replacement);
      }
    }
    return merge.document.copyWith(
      title: merge.titleConflict && _titleChoice == false
          ? current.title
          : merge.document.title,
      blocks: blocks,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final local =
        _current ??
        BlockDocument(
          id: widget.proposal.targetDocumentId,
          title: '',
          blocks: const [],
        );
    final proposed = widget.proposal.content;
    final rows = alignBlocks(local, proposed);

    if (_loading) {
      return Scaffold(
        backgroundColor: colors.appBackground,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpace.pane,
              DsSpace.pane,
              DsSpace.pane,
              DsSpace.islandGap / 2,
            ),
            child: Row(
              children: [
                Text(
                  local.title,
                  style: uiTextStyle(size: 14, weight: 600, color: colors.text),
                ),
                const SizedBox(width: 10),
                Text(
                  'proposed by ${widget.proposal.authorDisplayName}',
                  style: uiTextStyle(size: 12, color: colors.muted),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.pane),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _Pane(
                      label: 'Current file',
                      children: [
                        for (final row in rows)
                          _DiffBlock(block: row.local, kind: row.leftKind),
                      ],
                    ),
                  ),
                  const SizedBox(width: DsSpace.islandGap),
                  Expanded(
                    child: _Pane(
                      label: 'Proposed revision',
                      children: [
                        for (final row in rows)
                          _DiffBlock(block: row.proposed, kind: row.rightKind),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.pane),
              child: DsErrorBox(_error!),
            ),
          if (_merge?.hasConflicts ?? false)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DsSpace.pane,
                8,
                DsSpace.pane,
                0,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_merge!.titleConflict)
                    _ConflictChoice(
                      label: 'Title',
                      selected: _titleChoice,
                      onChanged: (choice) =>
                          setState(() => _titleChoice = choice),
                    ),
                  for (final id in _merge!.conflictedBlockIds)
                    _ConflictChoice(
                      label: 'Block',
                      selected: _conflictChoices[id],
                      onChanged: (choice) =>
                          setState(() => _conflictChoices[id] = choice),
                    ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpace.pane,
              8,
              DsSpace.pane,
              0,
            ),
            child: TextField(
              controller: _reviewNote,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Optional review note',
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.pane),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DsLabelButton(
                  label: 'Approve',
                  onPressed:
                      _working || _error != null || _resolvedMerge() == null
                      ? null
                      : _approve,
                  horizontalPadding: 18,
                ),
                const SizedBox(width: DsSpace.islandGap),
                DsLabelButton(
                  label: 'Reject',
                  onPressed: _working ? null : _reject,
                  horizontalPadding: 18,
                ),
                const SizedBox(width: DsSpace.islandGap),
                DsLabelButton(
                  label: 'Return',
                  onPressed: _working ? null : _return,
                  horizontalPadding: 18,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictChoice extends StatelessWidget {
  const _ConflictChoice({
    required this.label,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final bool? selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text('$label conflict'),
      const SizedBox(width: 6),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('Current')),
          ButtonSegment(value: true, label: Text('Proposed')),
        ],
        emptySelectionAllowed: true,
        selected: selected == null ? const {} : {selected!},
        onSelectionChanged: (selection) {
          if (selection.isNotEmpty) onChanged(selection.first);
        },
      ),
    ],
  );
}

// ------------------------------------------------------------- diff model --

enum DiffKind { unchanged, added, removed, changed, absent }

class DiffRow {
  const DiffRow({
    required this.local,
    required this.proposed,
    required this.leftKind,
    required this.rightKind,
  });

  final Block? local;
  final Block? proposed;
  final DiffKind leftKind;
  final DiffKind rightKind;
}

/// Pairs the two documents' blocks by id so the panes line up, and labels each
/// side. Ids make this exact: a paragraph that only moved is not reported as a
/// deletion plus an insertion.
List<DiffRow> alignBlocks(BlockDocument local, BlockDocument proposed) {
  final localById = {for (final b in local.blocks) b.id: b};
  final proposedById = {for (final b in proposed.blocks) b.id: b};

  final order = local.blocks.map((block) => block.id).toList();
  final known = order.toSet();
  for (var i = 0; i < proposed.blocks.length; i++) {
    final id = proposed.blocks[i].id;
    if (!known.add(id)) continue;
    final predecessor = i == 0 ? null : proposed.blocks[i - 1].id;
    final at = predecessor == null ? 0 : order.indexOf(predecessor) + 1;
    order.insert(at.clamp(0, order.length), id);
  }

  return [for (final id in order) _alignedRow(localById[id], proposedById[id])];
}

DiffRow _alignedRow(Block? local, Block? proposed) {
  if (local == null) {
    return DiffRow(
      local: null,
      proposed: proposed,
      leftKind: DiffKind.absent,
      rightKind: DiffKind.added,
    );
  }
  if (proposed == null) {
    return DiffRow(
      local: local,
      proposed: null,
      leftKind: DiffKind.removed,
      rightKind: DiffKind.absent,
    );
  }

  final same = local.sameContentAs(proposed);
  final kind = same ? DiffKind.unchanged : DiffKind.changed;
  return DiffRow(
    local: local,
    proposed: proposed,
    leftKind: kind,
    rightKind: kind,
  );
}

// -------------------------------------------------------------------- views --

class _Pane extends StatelessWidget {
  const _Pane({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      decoration: BoxDecoration(
        color: colors.editorSurface,
        borderRadius: const BorderRadius.all(DsRadius.island),
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Text(
              label,
              style: uiTextStyle(size: 12, weight: 600, color: colors.muted),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffBlock extends ConsumerWidget {
  const _DiffBlock({required this.block, required this.kind});

  final Block? block;
  final DiffKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;

    final background = switch (kind) {
      DiffKind.added => colors.addition,
      DiffKind.removed => colors.removal,
      DiffKind.changed => colors.conflict,
      DiffKind.unchanged || DiffKind.absent => Colors.transparent,
    };

    // Paragraphs and headings differ only in the base style the spans sit on.
    final child = switch (block) {
      final TextBlock t => Text.rich(
        TextSpan(
          children: [
            for (final span in t.spans)
              TextSpan(
                text: span.text,
                style: styleFor(
                  span,
                  t is HeadingBlock
                      ? headingStyle(t.level, colors.text)
                      : editorTextStyle(
                          size: 14,
                          height: 1.6,
                          color: colors.text,
                        ),
                  linkColor: colors.link,
                ),
              ),
          ],
        ),
        textAlign: switch (block!.align) {
          BlockAlign.left => TextAlign.left,
          BlockAlign.center => TextAlign.center,
          BlockAlign.right => TextAlign.right,
        },
      ),
      final CodeBlock c => Text(
        c.text,
        style: editorTextStyle(
          size: 13,
          height: 1.5,
          color: colors.text,
        ).copyWith(fontFamily: 'Courier New'),
      ),
      DividerBlock() => Divider(color: colors.border, height: 12),
      final TableBlock t => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final row in t.rows)
            Text(
              row.map((c) => c.map((s) => s.text).join()).join('  |  '),
              style: editorTextStyle(size: 13, height: 1.6, color: colors.text),
            ),
        ],
      ),
      final ImageBlock i => Text(
        i.caption.isEmpty ? '[image]' : '[image] ${i.caption}',
        style: editorTextStyle(size: 13, italic: true, color: colors.muted),
      ),
      null => const SizedBox(height: 20),
    };

    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(
        bottom: DsSpace.row,
        top: block?.spaceBefore ?? 0,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: const BorderRadius.all(DsRadius.row),
      ),
      child: child,
    );
  }
}
