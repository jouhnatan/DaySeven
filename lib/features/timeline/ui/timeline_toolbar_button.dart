/// Toolbar button to create or toggle the Timeline for the active document.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

const double _kToolbarIconSize = 14;

class TimelineToolbarButton extends ConsumerWidget {
  const TimelineToolbarButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(documentControllerProvider);
    final section = ref.watch(activeTimelineSectionProvider);
    final isCollapsed = ref.watch(isTimelineCollapsedProvider);
    final actions = ref.read(timelineActionControllerProvider);

    final hasDocument = open != null;
    final hasTimeline = section != null;

    final tooltip = !hasDocument
        ? 'Open a document to use Timeline'
        : hasTimeline
            ? (isCollapsed ? 'Expand Timeline' : 'Collapse Timeline')
            : 'Insert Timeline';

    return Tooltip(
      message: tooltip,
      child: DsButton(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        active: hasTimeline && !isCollapsed,
        onPressed: !hasDocument
            ? null
            : () {
                if (!hasTimeline) {
                  actions.createTimeline();
                } else {
                  ref.read(isTimelineCollapsedProvider.notifier).state =
                      !isCollapsed;
                }
              },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline,
              size: _kToolbarIconSize,
              color: !hasDocument
                  ? colors.faint
                  : (hasTimeline && !isCollapsed)
                      ? colors.onFern
                      : colors.text,
            ),
            const SizedBox(width: 4),
            Text(
              'Timeline',
              style: uiTextStyle(
                size: 12,
                weight: 500,
                color: !hasDocument
                    ? colors.faint
                    : (hasTimeline && !isCollapsed)
                        ? colors.onFern
                        : colors.text,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
