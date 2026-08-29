/// The bottom inspector and action bar for creating, editing, linking, and deleting timeline items.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/domain/timeline_model.dart';
import 'package:dayseven/features/timeline/domain/timeline_parser.dart';
import 'package:dayseven/features/timeline/ui/timeline_color_picker.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineInspector extends ConsumerStatefulWidget {
  const TimelineInspector({super.key});

  @override
  ConsumerState<TimelineInspector> createState() => _TimelineInspectorState();
}

class _TimelineInspectorState extends ConsumerState<TimelineInspector> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _startController = TextEditingController();
  final TextEditingController _endController = TextEditingController();

  String? _lastItemId;

  @override
  void dispose() {
    _titleController.dispose();
    _startController.dispose();
    _endController.dispose();
    super.dispose();
  }

  void _syncWithItem(TimelineItem? item) {
    if (item == null) {
      _lastItemId = null;
      _titleController.clear();
      _startController.clear();
      _endController.clear();
      return;
    }

    if (_lastItemId != item.id) {
      _lastItemId = item.id;
      _titleController.text = item.title;
      _startController.text = item.startDateLabel;
      if (item is TimelinePeriodItem) {
        _endController.text = item.endDateLabel;
      } else {
        _endController.clear();
      }
    }
  }

  Future<void> _showLinkDialog(BuildContext context, TimelineItem item) async {
    final linkField = TextEditingController(text: item.kbDocumentPath ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (context) => DsDialog(
        title: Text('Link to Knowledge Base Document', style: uiHeaderTextStyle(size: 16)),
        actions: [
          if (item.isDocumentLink)
            DsDialogAction(
              label: 'Remove Link',
              tone: DsDialogActionTone.danger,
              onPressed: () => Navigator.of(context).pop('__REMOVE__'),
            ),
          DsDialogAction(
            label: 'Cancel',
            tone: DsDialogActionTone.muted,
            onPressed: () => Navigator.of(context).pop(),
          ),
          DsDialogAction(
            label: 'Save Link',
            tone: DsDialogActionTone.normal,
            onPressed: () => Navigator.of(context).pop(linkField.text.trim()),
          ),
        ],
        children: [
          Text(
            'Enter the relative path to a markdown document in this Knowledge Base:',
            style: uiTextStyle(size: 13, color: context.ds.muted),
          ),
          const SizedBox(height: 12),
          DsField(
            controller: linkField,
            hint: 'e.g. Characters/Aldric.md',
            autofocus: true,
          ),
        ],
      ),
    );

    if (!mounted || result == null) return;
    final actions = ref.read(timelineActionControllerProvider);
    if (result == '__REMOVE__') {
      actions.updateItem(item.copyWith(clearKbDocumentPath: true));
    } else if (result.isNotEmpty) {
      actions.updateItem(item.copyWith(kbDocumentPath: result));
    }
  }

  void _onTitleChanged(TimelineItem item, String text) {
    if (text == item.title) return;
    ref.read(timelineActionControllerProvider).updateItem(
          item.copyWith(title: text),
        );
  }

  void _onStartDateChanged(TimelineItem item, String text) {
    if (text == item.startDateLabel) return;
    final parsedYear = TimelineParser.parseDateScalar(text);
    final year = parsedYear ?? item.startYear;
    ref.read(timelineActionControllerProvider).updateItem(
          item.copyWith(
            startDateLabel: text,
            startYear: year,
          ),
        );
  }

  void _onEndDateChanged(TimelinePeriodItem item, String text) {
    if (text == item.endDateLabel) return;
    final parsedYear = TimelineParser.parseDateScalar(text);
    final year = parsedYear ?? item.endYear;
    ref.read(timelineActionControllerProvider).updateItem(
          item.copyWith(
            endDateLabel: text,
            endYear: year,
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final selectedItem = ref.watch(selectedTimelineItemProvider);
    final actions = ref.read(timelineActionControllerProvider);

    _syncWithItem(selectedItem);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          // 1. Add Item (+) Button with Popup Menu
          PopupMenuButton<String>(
            tooltip: 'Add Timeline Item',
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(DsRadius.menu),
              side: BorderSide(color: CF.line),
            ),
            color: colors.island,
            onSelected: (value) {
              if (value == 'period') {
                actions.addItem(isPeriod: true);
              } else {
                actions.addItem(isPeriod: false);
              }
            },
            itemBuilder: (context) => [
              DsMenuItem<String>(
                value: 'event',
                height: kDsCompactMenuItemHeight,
                child: Row(
                  children: [
                    Icon(Icons.radio_button_checked, size: 14, color: colors.fern),
                    const SizedBox(width: 8),
                    Text('New Point Event', style: uiTextStyle(size: 13, color: colors.text)),
                  ],
                ),
              ),
              DsMenuItem<String>(
                value: 'period',
                height: kDsCompactMenuItemHeight,
                child: Row(
                  children: [
                    Icon(Icons.linear_scale, size: 14, color: colors.fern),
                    const SizedBox(width: 8),
                    Text('New Age / Period', style: uiTextStyle(size: 13, color: colors.text)),
                  ],
                ),
              ),
            ],
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.fern,
                borderRadius: const BorderRadius.all(DsRadius.control),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add, size: 16, color: colors.onFern),
                  const SizedBox(width: 4),
                  Text(
                    'Add',
                    style: uiTextStyle(size: 12.5, weight: 500, color: colors.onFern),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),

          if (selectedItem != null) ...[
            // 2. Title Field
            Expanded(
              flex: 3,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: colors.island,
                  borderRadius: const BorderRadius.all(DsRadius.control),
                  border: Border.all(color: colors.surfaceOutline),
                ),
                alignment: Alignment.centerLeft,
                child: TextField(
                  controller: _titleController,
                  onChanged: (text) => _onTitleChanged(selectedItem, text),
                  style: uiTextStyle(size: 13, weight: 500, color: colors.text),
                  cursorColor: colors.fern,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Item title...',
                    hintStyle: uiTextStyle(size: 13, color: colors.faint),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 3. Document Link Button (🔗)
            Tooltip(
              message: selectedItem.isDocumentLink
                  ? 'Linked to: ${selectedItem.kbDocumentPath}'
                  : 'Link to Knowledge Base document',
              child: DsButton(
                variant: selectedItem.isDocumentLink
                    ? DsButtonVariant.primary
                    : DsButtonVariant.secondary,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => _showLinkDialog(context, selectedItem),
                child: Icon(
                  Icons.link,
                  size: 16,
                  color: selectedItem.isDocumentLink ? colors.onFern : colors.text,
                ),
              ),
            ),
            const SizedBox(width: 6),

            // 4. Color Palette Picker Button (🎨)
            TimelineColorPicker(
              selectedColor: selectedItem.color,
              onColorSelected: (color) {
                actions.updateItem(selectedItem.copyWith(color: color));
              },
            ),
            const SizedBox(width: 8),

            // 5. Start Date Field
            Expanded(
              flex: 3,
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: colors.island,
                  borderRadius: const BorderRadius.all(DsRadius.control),
                  border: Border.all(color: colors.surfaceOutline),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 13, color: colors.muted),
                    const SizedBox(width: 6),
                    Expanded(
                      child: TextField(
                        controller: _startController,
                        onChanged: (text) => _onStartDateChanged(selectedItem, text),
                        keyboardType: const TextInputType.numberWithOptions(signed: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                        ],
                        style: uiTextStyle(size: 12, color: colors.text, tabular: true),
                        cursorColor: colors.fern,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          border: InputBorder.none,
                          hintText: 'Start date...',
                          hintStyle: uiTextStyle(size: 12, color: colors.faint),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 6. End Date (if Period) OR "+ End date" button (if Event)
            if (selectedItem is TimelinePeriodItem) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 14, color: colors.muted),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: colors.island,
                    borderRadius: const BorderRadius.all(DsRadius.control),
                    border: Border.all(color: colors.surfaceOutline),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 13, color: colors.muted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _endController,
                          onChanged: (text) => _onEndDateChanged(selectedItem, text),
                          keyboardType: const TextInputType.numberWithOptions(signed: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                          ],
                          style: uiTextStyle(size: 12, color: colors.text, tabular: true),
                          cursorColor: colors.fern,
                          decoration: InputDecoration(
                            isCollapsed: true,
                            border: InputBorder.none,
                            hintText: 'End date...',
                            hintStyle: uiTextStyle(size: 12, color: colors.faint),
                          ),
                        ),
                      ),
                      Tooltip(
                        message: 'Make point event',
                        child: GestureDetector(
                          onTap: () => actions.updateItem(selectedItem.toPoint()),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(Icons.close, size: 14, color: colors.muted),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 4),
              Tooltip(
                message: 'Stretch event over a period of time',
                child: DsButton(
                  variant: DsButtonVariant.secondary,
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  onPressed: () => actions.updateItem(selectedItem.toPeriod()),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.linear_scale, size: 14, color: colors.muted),
                      const SizedBox(width: 4),
                      Text(
                        '+ End date',
                        style: uiTextStyle(size: 11.5, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),

            // 7. Delete Button (🗑)
            Tooltip(
              message: 'Delete item',
              child: DsButton(
                variant: DsButtonVariant.danger,
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                onPressed: () => actions.removeItem(selectedItem.id),
                child: Icon(Icons.delete_outline, size: 16, color: colors.danger),
              ),
            ),
          ] else ...[
            Expanded(
              child: Text(
                'Select a point or period to edit details',
                style: uiTextStyle(size: 12.5, color: colors.muted),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
