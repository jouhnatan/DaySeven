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
  String? _error;

  /// Returning leaves the proposal exactly as it was found.
  void _return() => Navigator.of(context).pop();

  Future<void> _reject() async {
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      await ref.read(changeSetRepositoryProvider).reject(widget.proposal.id);
      ref.read(pendingProposalProvider.notifier).clear();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() {
        _error = describeError(error);
        _working = false;
      });
    }
  }

  Future<void> _approve() async {
    final open = ref.read(documentControllerProvider);
    final session = ref.read(kbSessionProvider);
    if (open == null || session == null) return;

    setState(() {
      _working = true;
      _error = null;
    });

    try {
      final documents = ref.read(documentRepositoryProvider);
      final base = await documents.revision(widget.proposal.baseRevisionId);
      if (base == null) {
        throw const SyncException(
          'The revision this was written against is gone.',
        );
      }
      final currentRevisionId = await documents.currentRevisionId(
        open.document.id,
      );

      final merge = threeWayMerge(
        base: base.content,
        local: open.document,
        proposed: widget.proposal.content,
      );

      await ref
          .read(changeSetRepositoryProvider)
          .approve(
            changeSetId: widget.proposal.id,
            merged: merge.document,
            expectedCurrentRevisionId: currentRevisionId,
          );

      // Only once the server has accepted the revision is the local file
      // rewritten, so a failed approval can never leave the folder ahead of the
      // history.
      await session.kb.writeDocument(open.relativePath, merge.document);
      session.index.upsert(open.relativePath, merge.document);
      await ref
          .read(documentControllerProvider.notifier)
          .open(open.relativePath);

      ref.read(pendingProposalProvider.notifier).clear();
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() {
        _error = describeError(error);
        _working = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final open = ref.watch(documentControllerProvider);
    final local =
        open?.document ?? const BlockDocument(id: '', title: '', blocks: []);
    final proposed = widget.proposal.content;
    final rows = alignBlocks(local, proposed);

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
                  style: aleo(size: 14, weight: 600, color: colors.text),
                ),
                const SizedBox(width: 10),
                Text(
                  'proposed by ${widget.proposal.authorDisplayName}',
                  style: aleo(size: 12, color: colors.muted),
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
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.pane),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Action(
                  label: 'Approve',
                  onPressed: _working ? null : _approve,
                ),
                const SizedBox(width: DsSpace.islandGap),
                _Action(label: 'Reject', onPressed: _working ? null : _reject),
                const SizedBox(width: DsSpace.islandGap),
                _Action(label: 'Return', onPressed: _working ? null : _return),
              ],
            ),
          ),
        ],
      ),
    );
  }
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

  final order = <String>[];
  for (final b in local.blocks) {
    order.add(b.id);
  }
  for (var i = 0; i < proposed.blocks.length; i++) {
    final id = proposed.blocks[i].id;
    if (order.contains(id)) continue;
    final predecessor = i == 0 ? null : proposed.blocks[i - 1].id;
    final at = predecessor == null ? 0 : order.indexOf(predecessor) + 1;
    order.insert(at.clamp(0, order.length), id);
  }

  return [
    for (final id in order)
      () {
        final l = localById[id];
        final p = proposedById[id];
        if (l == null) {
          return DiffRow(
            local: null,
            proposed: p,
            leftKind: DiffKind.absent,
            rightKind: DiffKind.added,
          );
        }
        if (p == null) {
          return DiffRow(
            local: l,
            proposed: null,
            leftKind: DiffKind.removed,
            rightKind: DiffKind.absent,
          );
        }
        final same = _sameBlock(l, p);
        return DiffRow(
          local: l,
          proposed: p,
          leftKind: same ? DiffKind.unchanged : DiffKind.changed,
          rightKind: same ? DiffKind.unchanged : DiffKind.changed,
        );
      }(),
  ];
}

bool _sameBlock(Block a, Block b) =>
    a.toJson().toString() == b.toJson().toString();

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
              style: aleo(size: 12, weight: 600, color: colors.muted),
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

    final child = switch (block) {
      final ParagraphBlock p => Text.rich(
        TextSpan(
          children: [
            for (final span in p.spans)
              TextSpan(
                text: span.text,
                style: styleFor(
                  span,
                  aleo(size: 14, height: 1.6, color: colors.text),
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
      final ImageBlock i => Text(
        i.caption.isEmpty ? '[image]' : '[image] ${i.caption}',
        style: aleo(size: 13, italic: true, color: colors.muted),
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

class _Action extends StatefulWidget {
  const _Action({required this.label, this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final enabled = widget.onPressed != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered && enabled ? colors.selection : colors.island,
            borderRadius: const BorderRadius.all(DsRadius.control),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: Text(
            widget.label,
            style: aleo(
              size: 13,
              weight: 500,
              color: enabled ? colors.text : colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
