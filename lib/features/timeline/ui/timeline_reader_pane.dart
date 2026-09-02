/// The right-hand pane of the Timelines view: what is being read, and what is
/// being read from.
///
/// One pane doing two jobs, chosen with a segmented control that sits where
/// the Knowledge Base pane keeps its folder dropdown. *Description* is the
/// selected event or age, and the document it stands for, shown rather than
/// edited. *Timelines* is the list of timeline objects in this Knowledge Base
/// — the directory, for a view whose directory is a short list rather than a
/// tree.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/domain/timeline.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/document_preview.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:dayseven/shared/ui/name_prompt.dart';
import 'package:dayseven/shared/ui/theme.dart';

enum _ReaderTab { description, timelines }

/// Matches the control height the Knowledge Base pane uses in the same slot,
/// so the two views' panes do not disagree about where their first row sits.
const double _kControlHeight = DsSize.smallControl;

/// The segmented strip stands 6px taller than its cells: 2px of inner padding
/// and 1px of border on each edge.
const double _kSegmentedCellHeight = _kControlHeight - 6;

class TimelineReaderPane extends ConsumerStatefulWidget {
  const TimelineReaderPane({super.key});

  @override
  ConsumerState<TimelineReaderPane> createState() => _TimelineReaderPaneState();
}

class _TimelineReaderPaneState extends ConsumerState<TimelineReaderPane> {
  // Which tab is showing is a property of this pane while it is on screen, not
  // something the rest of the app or the next launch has any use for.
  _ReaderTab _tab = _ReaderTab.description;

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openTimelineProvider);

    return DsPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DsMenuHeader(
            open == null ? 'Timelines' : open.timeline.title,
          ),
          // The strip holds the choice and nothing else. Each half's own
          // action lives with the thing it acts on, which is also the only way
          // this row fits the pane at its narrowest.
          Padding(
            padding: const EdgeInsets.all(DsSpace.row),
            child: SizedBox(
              key: const Key('timeline-reader-tabs'),
              height: _kControlHeight,
              child: Center(
                child: DsSegmented<_ReaderTab>(
                  value: _tab,
                  cellHeight: _kSegmentedCellHeight,
                  onPick: (tab) => setState(() => _tab = tab),
                  options: [
                    DsSegmentedOption(
                      value: _ReaderTab.description,
                      semanticLabel: 'Detail',
                      child: Text(
                        'Detail',
                        style: uiTextStyle(size: 12, weight: 500),
                      ),
                    ),
                    DsSegmentedOption(
                      value: _ReaderTab.timelines,
                      semanticLabel: 'Timelines',
                      child: Text(
                        'Timelines',
                        style: uiTextStyle(size: 12, weight: 500),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const DsSeam.horizontal(),
          Expanded(
            child: switch (_tab) {
              _ReaderTab.description => const TimelineDescriptionPanel(),
              _ReaderTab.timelines => const _TimelinesList(),
            },
          ),
        ],
      ),
    );
  }
}

/// The reading half of the pane, also used on its own when it is expanded over
/// the map canvas.
class TimelineDescriptionPanel extends ConsumerWidget {
  const TimelineDescriptionPanel({super.key, this.expanded = false});

  /// True when this is the full-view copy laid over the map, which has room
  /// for the document at its ordinary size.
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final item = ref.watch(selectedTimelineItemProvider);

    if (item == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.m),
          child: Text(
            'Select an event or an age on the timeline.',
            textAlign: TextAlign.center,
            style: uiTextStyle(size: 13, color: colors.faint),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      key: const Key('timeline-reader-description'),
      padding: const EdgeInsets.fromLTRB(
        DsSpace.m,
        DsSpace.m,
        DsSpace.m,
        DsSpace.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6, right: DsSpace.s),
                decoration: BoxDecoration(
                  color: item.color.color,
                  shape: BoxShape.circle,
                ),
              ),
              Expanded(
                child: Text(
                  item.title.isEmpty ? 'Untitled' : item.title,
                  style: uiHeaderTextStyle(
                    size: expanded ? 20 : 16,
                    weight: 600,
                    color: colors.text,
                  ),
                ),
              ),
              // The expanded copy has its own Retract control in the header
              // above it; a second one here would be two ways to do one thing.
              if (!expanded) const _ExpandReaderButton(),
            ],
          ),
          const SizedBox(height: DsSpace.xxs),
          Text(
            switch (item) {
              final TimelinePeriodItem p =>
                '${p.startDateLabel} → ${p.endDateLabel}',
              final TimelineEventItem e => e.startDateLabel,
            },
            style: uiTextStyle(size: 12, color: colors.muted, tabular: true),
          ),
          const SizedBox(height: DsSpace.sm),
          const DsSeam.horizontal(),
          const SizedBox(height: DsSpace.sm),
          _ItemBody(item: item, expanded: expanded),
        ],
      ),
    );
  }
}

/// The linked document, the item's own words, or a line saying there are
/// neither.
class _ItemBody extends ConsumerWidget {
  const _ItemBody({required this.item, required this.expanded});

  final TimelineItem item;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;

    if (!item.isDocumentLink) {
      return Text(
        item.description.isEmpty
            ? 'No description, and no document linked.'
            : item.description,
        style: uiTextStyle(
          size: 13,
          height: 1.5,
          color: item.description.isEmpty ? colors.faint : colors.text,
        ),
      );
    }

    final document = ref.watch(timelineReaderDocumentProvider);

    return document.when(
      loading: () => Text(
        'Reading ${item.documentPath}…',
        style: uiTextStyle(size: 13, color: colors.faint),
      ),
      error: (_, _) => DsErrorBox('Could not read ${item.documentPath}.'),
      data: (document) {
        if (document == null) {
          return DsErrorBox(
            'This item links to "${item.documentPath}", which is no longer '
            'in the Knowledge Base.',
          );
        }
        return DsDocumentPreview(document: document, compact: !expanded);
      },
    );
  }
}

/// The list of timeline objects: this view's directory.
class _TimelinesList extends ConsumerWidget {
  const _TimelinesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final objects = ref.watch(timelineObjectsProvider);
    final openPath = ref.watch(openTimelineProvider)?.relativePath;

    return objects.when(
      loading: () => const SizedBox.shrink(),
      error: (error, _) => Padding(
        padding: const EdgeInsets.all(DsSpace.sm),
        child: DsErrorBox('$error'),
      ),
      data: (files) {
        if (files.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.all(DsSpace.row),
                child: _NewTimelineButton(),
              ),
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(DsSpace.m),
                    child: Text(
                      'No timelines yet.',
                      textAlign: TextAlign.center,
                      style: uiTextStyle(size: 13, color: colors.faint),
                    ),
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(
                DsSpace.row,
                DsSpace.row,
                DsSpace.row,
                0,
              ),
              child: _NewTimelineButton(),
            ),
            Expanded(
              child: ListView.builder(
                key: const Key('timeline-objects-list'),
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpace.row,
                  vertical: DsSpace.row,
                ),
                itemCount: files.length,
                itemBuilder: (context, index) => _TimelineRow(
                  file: files[index],
                  selected: files[index].relativePath == openPath,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

enum _RowAction { rename, delete }

class _TimelineRow extends ConsumerWidget {
  const _TimelineRow({required this.file, required this.selected});

  final KbFile file;
  final bool selected;

  Future<void> _showMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    final menu = DsDropdownMenuList<_RowAction>();
    menu.pushItem(
      key: const Key('timeline-row-rename'),
      value: _RowAction.rename,
      label: 'Rename…',
    );
    menu.pushItem(
      key: const Key('timeline-row-delete'),
      value: _RowAction.delete,
      label: 'Delete',
      isDestructive: true,
    );

    final choice = await menu.show(context, position: position);
    if (!context.mounted || choice == null) return;

    switch (choice) {
      case _RowAction.rename:
        await _rename(context, ref);
      case _RowAction.delete:
        await _delete(context, ref);
    }
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await askForName(
      context,
      title: 'Rename timeline',
      initial: objectNameFromPath(file.relativePath),
      actionLabel: 'Rename',
    );
    if (name == null || !context.mounted) return;

    await _guard(context, () async {
      final destination = await ref
          .read(kbControllerProvider.notifier)
          .renameObject(file.relativePath, name);
      // The pane orchestrates its own state rather than the Knowledge Base
      // reaching into a feature it is not allowed to know about.
      ref
          .read(openTimelineProvider.notifier)
          .relocate(
            file.relativePath,
            destination,
            title: objectNameFromPath(destination),
          );
    });
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final name = objectNameFromPath(file.relativePath);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DsDialog(
        title: Text('Delete timeline', style: uiHeaderTextStyle(size: 16)),
        actions: [
          DsDialogAction(
            label: 'Cancel',
            tone: DsDialogActionTone.muted,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          DsDialogAction(
            label: 'Delete',
            tone: DsDialogActionTone.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        children: [
          Text(
            'Delete "$name"? The documents its events point at are not '
            'touched — only the timeline itself goes.',
            style: uiTextStyle(size: 13, color: context.ds.muted),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await _guard(context, () async {
      // Close first: the controller's pending save must not put the file back
      // after the delete has taken it away.
      ref.read(openTimelineProvider.notifier).closeIfOpen(file.relativePath);
      await ref
          .read(kbControllerProvider.notifier)
          .deleteNode(file.relativePath);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final name = objectNameFromPath(file.relativePath);
    final folder = _folderOf(file.relativePath);

    return GestureDetector(
      onSecondaryTapDown: (details) =>
          unawaited(_showMenu(context, ref, details.globalPosition)),
      child: DsHoverRow(
        key: Key('timeline-row-${file.relativePath}'),
        selected: selected,
        semanticLabel: name,
        padding: const EdgeInsets.symmetric(
          horizontal: DsSpace.s,
          vertical: DsSpace.row,
        ),
        onTap: () => unawaited(
          ref.read(openTimelineProvider.notifier).open(file.relativePath),
        ),
        child: Row(
          children: [
            Icon(
              Icons.timeline,
              size: 16,
              color: selected ? colors.fern : colors.muted,
            ),
            const SizedBox(width: DsSpace.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: uiTextStyle(
                      size: 13,
                      weight: selected ? 600 : 400,
                      color: colors.text,
                    ),
                  ),
                  if (folder.isNotEmpty)
                    Text(
                      folder,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: uiTextStyle(size: 11, color: colors.faint),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The folder a path sits in, or empty at the root. Written out rather than
/// importing `package:path` for one call.
String _folderOf(String relativePath) {
  final cut = relativePath.lastIndexOf('/');
  return cut < 0 ? '' : relativePath.substring(0, cut);
}

class _NewTimelineButton extends ConsumerWidget {
  const _NewTimelineButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kbSessionProvider);

    final colors = context.ds;

    return Tooltip(
      message: session == null
          ? 'Open a Knowledge Base first'
          : 'Make a new timeline in this Knowledge Base',
      child: DsButton(
        key: const Key('timeline-new-button'),
        height: _kControlHeight,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.gap),
        onPressed: session == null
            ? null
            : () => unawaited(
                _guard(context, () async {
                  final path = await ref
                      .read(kbControllerProvider.notifier)
                      .createObject(
                        name: kNewTimelineName,
                        seed: newTimelineSeed(),
                      );
                  await ref.read(openTimelineProvider.notifier).open(path);
                }),
              ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add,
              size: 15,
              color: session == null ? colors.faint : colors.text,
            ),
            const SizedBox(width: DsSpace.row),
            Text(
              'New timeline',
              style: uiTextStyle(
                size: 12,
                weight: 500,
                color: session == null ? colors.faint : colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandReaderButton extends ConsumerWidget {
  const _ExpandReaderButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expanded = ref.watch(readerExpandedProvider);
    final hasItem = ref.watch(selectedTimelineItemProvider) != null;

    return Tooltip(
      message: expanded ? 'Retract' : 'Expand to full view',
      child: SizedBox.square(
        dimension: _kControlHeight,
        child: DsButton(
          key: const Key('timeline-reader-expand-button'),
          height: _kControlHeight,
          padding: EdgeInsets.zero,
          active: expanded,
          onPressed: !hasItem
              ? null
              : () => ref.read(readerExpandedProvider.notifier).state =
                    !expanded,
          child: Icon(
            expanded ? Icons.close_fullscreen : Icons.open_in_full,
            size: 15,
            color: !hasItem
                ? context.ds.faint
                : expanded
                ? context.ds.onFern
                : context.ds.text,
          ),
        ),
      ),
    );
  }
}

/// Runs a filesystem action and puts a failure on screen rather than into the
/// console. These all touch the user's own folder, where a failure is
/// something they can act on.
Future<void> _guard(BuildContext context, Future<void> Function() run) async {
  try {
    await run();
  } on KbException catch (error) {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: DsErrorBox(error.message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}
