/// The main Timeline widget embedded in the editor pane above the document canvas.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/ui/timeline_inspector.dart';
import 'package:dayseven/features/timeline/ui/timeline_popover.dart';
import 'package:dayseven/features/timeline/ui/timeline_track.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineWidget extends ConsumerWidget {
  const TimelineWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final section = ref.watch(activeTimelineSectionProvider);
    final selectedItem = ref.watch(selectedTimelineItemProvider);
    final isCollapsed = ref.watch(isTimelineCollapsedProvider);
    final actions = ref.read(timelineActionControllerProvider);

    if (section == null) {
      return const SizedBox.shrink();
    }

    return Container(
      key: const Key('timeline-widget-container'),
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: colors.island,
        borderRadius: const BorderRadius.all(DsRadius.island),
        border: Border.all(color: colors.surfaceOutline),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
            child: Row(
              children: [
                Icon(Icons.timeline, size: 18, color: colors.fern),
                const SizedBox(width: 8),
                Text(
                  'Timeline',
                  style: uiHeaderTextStyle(
                    size: 14.5,
                    weight: 600,
                    color: colors.text,
                  ),
                ),
                if (section.description.isNotEmpty) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colors.cardSurface,
                        borderRadius: const BorderRadius.all(DsRadius.row),
                        border: Border.all(color: colors.border),
                      ),
                      child: Text(
                        section.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: uiTextStyle(
                          size: 12,
                          color: colors.muted,
                        ),
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 8),
                // Collapse / Expand toggle button
                Tooltip(
                  message: isCollapsed ? 'Expand timeline' : 'Collapse timeline',
                  child: DsButton(
                    variant: DsButtonVariant.quiet,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    onPressed: () {
                      ref.read(isTimelineCollapsedProvider.notifier).state =
                          !isCollapsed;
                    },
                    child: Icon(
                      isCollapsed ? Icons.expand_more : Icons.expand_less,
                      size: 18,
                      color: colors.muted,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Remove Timeline button
                Tooltip(
                  message: 'Remove timeline from document',
                  child: DsButton(
                    variant: DsButtonVariant.quiet,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    onPressed: () => _confirmRemoveTimeline(context, ref),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.delete_outline,
                          size: 16,
                          color: colors.danger,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Remove',
                          style: uiTextStyle(
                            size: 12,
                            weight: 500,
                            color: colors.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          if (!isCollapsed) ...[
            const Divider(height: 1),
            // 2. Horizontal Timeline Track
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: TimelineTrack(section: section),
            ),

            // 3. Detail Popover (if an item is selected)
            if (selectedItem != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: Center(
                  child: TimelinePopover(
                    item: selectedItem,
                    onClose: () => actions.selectItem(null),
                  ),
                ),
              ),
            ],

            const Divider(height: 1),
            // 4. Bottom Inspector / Action Toolbar
            const Padding(
              padding: EdgeInsets.all(8),
              child: TimelineInspector(),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmRemoveTimeline(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => DsDialog(
        title: Text(
          'Remove Timeline',
          style: uiHeaderTextStyle(size: 16),
        ),
        actions: [
          DsDialogAction(
            label: 'Cancel',
            tone: DsDialogActionTone.muted,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          DsDialogAction(
            label: 'Remove Timeline',
            tone: DsDialogActionTone.danger,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
        children: [
          Text(
            'Are you sure you want to remove the timeline from this document? The timeline section and all its milestones will be deleted.',
            style: uiTextStyle(size: 13, color: context.ds.muted),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(timelineActionControllerProvider).removeTimeline();
    }
  }
}
