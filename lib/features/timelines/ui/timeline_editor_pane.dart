/// The left pane of the Timelines view: where an event or an age is edited.
///
/// Everything that changes a timeline happens here. The track along the bottom
/// selects and can drag a thing through time, and the centre is the map — but
/// the dates, the nations and the documents are set in one place, so there is
/// no hunting for which surface owns which field.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/domain/timeline.dart';
import 'package:dayseven/features/timelines/ui/timeline_color_picker.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/name_prompt.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineEditorPane extends ConsumerWidget {
  const TimelineEditorPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(openTimelineProvider);
    final item = ref.watch(selectedTimelineItemProvider);

    return DsPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DsMenuHeader('Events & ages'),
          if (open == null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(DsSpace.m),
                  child: Text(
                    'No timeline open.',
                    textAlign: TextAlign.center,
                    style: uiTextStyle(size: 13, color: colors.faint),
                  ),
                ),
              ),
            )
          else ...[
            const _AddRow(),
            const DsSeam.horizontal(),
            Expanded(
              child: item == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(DsSpace.m),
                        child: Text(
                          'Select something on the timeline to edit it.',
                          textAlign: TextAlign.center,
                          style: uiTextStyle(size: 13, color: colors.faint),
                        ),
                      ),
                    )
                  : _ItemEditor(
                      // A fresh set of text controllers per item, rather than
                      // one set reset by hand on every selection change.
                      key: ValueKey(item.id),
                      timeline: open.timeline,
                      item: item,
                    ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AddRow extends ConsumerWidget {
  const _AddRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final actions = ref.read(timelineActionControllerProvider);

    Widget button(String label, IconData icon, bool isPeriod, Key key) =>
        Expanded(
          child: DsButton(
            key: key,
            height: DsSize.smallControl,
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.row),
            onPressed: () => actions.addItem(isPeriod: isPeriod),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 14, color: colors.text),
                const SizedBox(width: DsSpace.row),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: uiTextStyle(size: 12, weight: 500, color: colors.text),
                  ),
                ),
              ],
            ),
          ),
        );

    return Padding(
      padding: const EdgeInsets.all(DsSpace.row),
      child: Row(
        children: [
          // Said as "Add" so this row cannot be mistaken for the Event/Age
          // control below it, which sets what the selected thing already is.
          button(
            'Add event',
            Icons.add,
            false,
            const Key('timeline-add-event'),
          ),
          const SizedBox(width: DsSpace.row),
          button('Add age', Icons.add, true, const Key('timeline-add-age')),
        ],
      ),
    );
  }
}

class _ItemEditor extends ConsumerStatefulWidget {
  const _ItemEditor({super.key, required this.timeline, required this.item});

  final Timeline timeline;
  final TimelineItem item;

  @override
  ConsumerState<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends ConsumerState<_ItemEditor> {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.item.title);
    _title.addListener(_commitTitle);
  }

  @override
  void dispose() {
    _title
      ..removeListener(_commitTitle)
      ..dispose();
    super.dispose();
  }

  TimelineActionController get _actions =>
      ref.read(timelineActionControllerProvider);

  void _commitTitle() {
    if (_title.text == widget.item.title) return;
    _actions.updateItem(widget.item.copyWith(title: _title.text));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DsDialog(
        title: Text(
          widget.item.isPeriod ? 'Delete age' : 'Delete event',
          style: uiHeaderTextStyle(size: 16),
        ),
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
            'Delete "${widget.item.title.isEmpty ? 'Untitled' : widget.item.title}"'
            ' from this timeline? The documents it connects to are not touched.',
            style: uiTextStyle(size: 13, color: context.ds.muted),
          ),
        ],
      ),
    );
    if (confirmed == true) _actions.removeItem(widget.item.id);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final item = widget.item;
    final period = item is TimelinePeriodItem ? item : null;

    return ListView(
      key: const Key('timeline-item-editor'),
      padding: const EdgeInsets.fromLTRB(
        DsSpace.sm,
        DsSpace.sm,
        DsSpace.sm,
        DsSpace.xxl,
      ),
      children: [
        Row(
          children: [
            Expanded(
              child: DsSegmented<bool>(
                value: item.isPeriod,
                cellHeight: 26,
                onPick: (isPeriod) {
                  if (isPeriod == item.isPeriod) return;
                  _actions.updateItem(
                    isPeriod ? item.toPeriod() : item.toPoint(),
                  );
                },
                options: [
                  DsSegmentedOption(
                    value: false,
                    semanticLabel: 'Event',
                    child: Text(
                      'Event',
                      style: uiTextStyle(size: 12, weight: 500),
                    ),
                  ),
                  DsSegmentedOption(
                    value: true,
                    semanticLabel: 'Age',
                    child: Text(
                      'Age',
                      style: uiTextStyle(size: 12, weight: 500),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: DsSpace.row),
            TimelineColorPicker(
              selectedColor: item.color,
              onColorSelected: (color) =>
                  _actions.updateItem(item.copyWith(color: color)),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.sm),

        _FieldLabel(item.isPeriod ? 'Name of the age' : 'Name of the event'),
        DsField(
          key: const Key('timeline-item-title'),
          controller: _title,
          hint: item.isPeriod ? 'New age' : 'New event',
        ),
        const SizedBox(height: DsSpace.s),

        _FieldLabel(period == null ? 'When' : 'Begins'),
        _DateRow(
          yearKey: const Key('timeline-item-year'),
          monthKey: const Key('timeline-item-month'),
          year: item.year,
          month: item.month,
          onChanged: (year, month, clearMonth) => _actions.updateItem(
            item.copyWith(year: year, month: month, clearMonth: clearMonth),
          ),
        ),

        if (period != null) ...[
          const SizedBox(height: DsSpace.s),
          const _FieldLabel('Ends'),
          _DateRow(
            yearKey: const Key('timeline-item-end-year'),
            monthKey: const Key('timeline-item-end-month'),
            year: period.endYear,
            month: period.endMonth,
            onChanged: (year, month, clearMonth) => _actions.updateItem(
              period.copyWith(
                endYear: year,
                endMonth: month,
                clearEndMonth: clearMonth,
              ),
            ),
          ),
        ],

        const SizedBox(height: DsSpace.m),
        _NationsSection(timeline: widget.timeline, item: item),

        const SizedBox(height: DsSpace.m),
        _DocumentsSection(item: item),

        const SizedBox(height: DsSpace.l),
        DsButton(
          key: const Key('timeline-item-delete'),
          height: DsSize.smallControl,
          onPressed: _confirmDelete,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.delete_outline, size: 15, color: colors.danger),
              const SizedBox(width: DsSpace.row),
              Text(
                item.isPeriod ? 'Delete age' : 'Delete event',
                style: uiTextStyle(size: 12, weight: 500, color: colors.danger),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A year and an optional month, side by side.
class _DateRow extends StatefulWidget {
  const _DateRow({
    required this.yearKey,
    required this.monthKey,
    required this.year,
    required this.month,
    required this.onChanged,
  });

  final Key yearKey;
  final Key monthKey;
  final int year;
  final int? month;

  /// `clearMonth` is what an emptied month field means: dated to the year, and
  /// no finer. It cannot be said with a null [month] alone, which copyWith
  /// reads as "leave it alone".
  final void Function(int? year, int? month, bool clearMonth) onChanged;

  @override
  State<_DateRow> createState() => _DateRowState();
}

class _DateRowState extends State<_DateRow> {
  late final TextEditingController _year;
  late final TextEditingController _month;

  @override
  void initState() {
    super.initState();
    _year = TextEditingController(text: '${widget.year}');
    _month = TextEditingController(text: widget.month?.toString() ?? '');
    _year.addListener(_commit);
    _month.addListener(_commit);
  }

  @override
  void dispose() {
    _year
      ..removeListener(_commit)
      ..dispose();
    _month
      ..removeListener(_commit)
      ..dispose();
    super.dispose();
  }

  void _commit() {
    final year = int.tryParse(_year.text.trim());
    final monthText = _month.text.trim();
    final month = int.tryParse(monthText);
    // A half-typed "-" is not a year yet; leave the item alone until it is.
    if (year == null) return;
    widget.onChanged(
      year,
      month != null && month > 0 ? month : null,
      monthText.isEmpty || month == null || month < 1,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 3,
          child: DsField(
            key: widget.yearKey,
            controller: _year,
            hint: 'Year',
          ),
        ),
        const SizedBox(width: DsSpace.row),
        Expanded(
          flex: 2,
          child: DsField(
            key: widget.monthKey,
            controller: _month,
            hint: 'Month',
          ),
        ),
      ],
    );
  }
}

/// The nations party to this item, chosen from the ones the timeline defines.
class _NationsSection extends ConsumerWidget {
  const _NationsSection({required this.timeline, required this.item});

  final Timeline timeline;
  final TimelineItem item;

  Future<void> _addNation(BuildContext context, WidgetRef ref) async {
    final name = await askForName(
      context,
      title: 'New nation',
      actionLabel: 'Add',
    );
    if (name == null || name.trim().isEmpty) return;

    final actions = ref.read(timelineActionControllerProvider);
    final nation = actions.addNation(name);
    if (nation == null) return;
    // Named from this item, so it belongs to this item.
    final current = ref.read(selectedTimelineItemProvider);
    if (current != null && !current.nationIds.contains(nation.id)) {
      actions.toggleNationOnItem(current, nation.id);
    }
  }

  Future<void> _nationMenu(
    BuildContext context,
    WidgetRef ref,
    TimelineNation nation,
    Offset position,
  ) async {
    final menu = DsDropdownMenuList<String>();
    menu.pushItem(value: 'rename', label: 'Rename…');
    menu.pushItem(
      value: 'delete',
      label: 'Remove from timeline',
      isDestructive: true,
    );

    final choice = await menu.show(context, position: position);
    if (!context.mounted || choice == null) return;

    final actions = ref.read(timelineActionControllerProvider);
    if (choice == 'delete') {
      actions.removeNation(nation.id);
      return;
    }
    final name = await askForName(
      context,
      title: 'Rename nation',
      initial: nation.name,
      actionLabel: 'Rename',
    );
    if (name == null || name.trim().isEmpty) return;
    actions.updateNation(nation.copyWith(name: name.trim()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _FieldLabel('Nations involved')),
            DsButton(
              key: const Key('timeline-add-nation'),
              variant: DsButtonVariant.quiet,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.row),
              onPressed: () => unawaited(_addNation(context, ref)),
              child: Icon(Icons.add, size: 14, color: colors.muted),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.xs),
        if (timeline.nations.isEmpty)
          Text(
            'None defined yet. Press + to name one.',
            style: uiTextStyle(size: 12, color: colors.faint),
          )
        else
          Wrap(
            key: const Key('timeline-nations'),
            spacing: DsSpace.row,
            runSpacing: DsSpace.row,
            children: [
              for (final nation in timeline.nations)
                _NationChip(
                  nation: nation,
                  selected: item.nationIds.contains(nation.id),
                  onTap: () => ref
                      .read(timelineActionControllerProvider)
                      .toggleNationOnItem(item, nation.id),
                  onMenu: (position) =>
                      unawaited(_nationMenu(context, ref, nation, position)),
                ),
            ],
          ),
      ],
    );
  }
}

class _NationChip extends StatelessWidget {
  const _NationChip({
    required this.nation,
    required this.selected,
    required this.onTap,
    required this.onMenu,
  });

  final TimelineNation nation;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset> onMenu;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return GestureDetector(
      onTap: onTap,
      onSecondaryTapDown: (details) => onMenu(details.globalPosition),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: Container(
          key: Key('timeline-nation-${nation.id}'),
          padding: const EdgeInsets.symmetric(
            horizontal: DsSpace.s,
            vertical: DsSpace.xs,
          ),
          decoration: BoxDecoration(
            color: selected ? nation.color.color : colors.cardSurface,
            borderRadius: const BorderRadius.all(DsRadius.pill),
            border: Border.all(
              color: selected ? nation.color.color : colors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!selected)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(right: DsSpace.xs),
                  decoration: BoxDecoration(
                    color: nation.color.color,
                    shape: BoxShape.circle,
                  ),
                ),
              Text(
                nation.name,
                style: uiTextStyle(
                  size: 12,
                  weight: selected ? 600 : 400,
                  color: selected ? colors.onFern : colors.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The documents this item connects to, the main one marked.
class _DocumentsSection extends ConsumerWidget {
  const _DocumentsSection({required this.item});

  final TimelineItem item;

  Future<void> _link(BuildContext context, WidgetRef ref) async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    final linked = item.allDocumentPaths.toSet();
    final available = [
      for (final path in documentPathsIn(session.tree))
        if (!linked.contains(path)) path,
    ];

    if (available.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => DsDialog(
          title: Text('Connect a document', style: uiHeaderTextStyle(size: 16)),
          actions: [
            DsDialogAction(
              label: 'OK',
              tone: DsDialogActionTone.muted,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
          children: [
            Text(
              linked.isEmpty
                  ? 'This Knowledge Base has no documents yet.'
                  : 'Every document in this Knowledge Base is already '
                        'connected to this item.',
              style: uiTextStyle(size: 13, color: context.ds.muted),
            ),
          ],
        ),
      );
      return;
    }

    final menu = DsDropdownMenuList<String>();
    for (final path in available) {
      menu.pushItem(value: path, label: path);
    }
    final choice = await menu.show(context);
    if (choice == null) return;
    ref.read(timelineActionControllerProvider).linkDocument(item, choice);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final paths = item.allDocumentPaths;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: _FieldLabel('Documents')),
            DsButton(
              key: const Key('timeline-link-document'),
              variant: DsButtonVariant.quiet,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.row),
              onPressed: () => unawaited(_link(context, ref)),
              child: Icon(Icons.add, size: 14, color: colors.muted),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.xs),
        if (paths.isEmpty)
          Text(
            'None connected. The item\'s own description is read instead.',
            style: uiTextStyle(size: 12, color: colors.faint),
          )
        else
          for (final path in paths)
            _DocumentRow(
              item: item,
              path: path,
              isMain: path == item.mainDocumentPath,
            ),
      ],
    );
  }
}

class _DocumentRow extends ConsumerWidget {
  const _DocumentRow({
    required this.item,
    required this.path,
    required this.isMain,
  });

  final TimelineItem item;
  final String path;
  final bool isMain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final actions = ref.read(timelineActionControllerProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.xs),
      child: Row(
        children: [
          Tooltip(
            message: isMain
                ? 'The main document: what the reader shows'
                : 'Make this the main document',
            child: DsButton(
              key: Key('timeline-main-doc-$path'),
              variant: DsButtonVariant.quiet,
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.xs),
              onPressed: isMain ? null : () => actions.makeMainDocument(item, path),
              child: Icon(
                isMain ? Icons.star : Icons.star_border,
                size: 15,
                color: isMain ? colors.fern : colors.faint,
              ),
            ),
          ),
          const SizedBox(width: DsSpace.xs),
          Expanded(
            child: Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: uiTextStyle(
                size: 12,
                weight: isMain ? 500 : 400,
                color: colors.text,
              ),
            ),
          ),
          DsButton(
            key: Key('timeline-unlink-$path'),
            variant: DsButtonVariant.quiet,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: DsSpace.xs),
            onPressed: () => actions.unlinkDocument(item, path),
            child: Icon(Icons.close, size: 13, color: colors.muted),
          ),
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.xs),
      child: Text(
        text,
        style: uiTextStyle(size: 11.5, weight: 500, color: context.ds.muted),
      ),
    );
  }
}
