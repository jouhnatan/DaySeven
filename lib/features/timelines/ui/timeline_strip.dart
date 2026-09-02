/// The timeline itself, across the bottom of the Timelines view.
///
/// A band carrying the track and nothing else, which is what the view is for:
/// the timeline is the constant, and the map and the two panes above it are
/// what change as you move along it.
///
/// The track selects and can drag a thing through time. It does not edit one —
/// that is the left pane's job — and it never takes the centre, which belongs
/// to the map.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timelines/application/timeline_controller.dart';
import 'package:dayseven/features/timelines/ui/timeline_track.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// The height of the track in the closed band.
const double kTimelineStripTrackHeight = 132;

/// The band's own header row, which names the open timeline and counts it.
const double kTimelineStripHeaderHeight = DsSize.smallControl + DsSpace.s;

/// The closed band across the bottom of the window.
class TimelineStrip extends ConsumerWidget {
  const TimelineStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openTimelineProvider);

    return Column(
      key: const Key('timeline-strip'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StripHeader(),
        SizedBox(
          height: kTimelineStripTrackHeight,
          child: open == null
              ? const _NoTimeline()
              : TimelineTrack(
                  // Rebuilt when a different timeline opens, so the scroll
                  // offset does not carry over from the last one.
                  key: ValueKey(open.relativePath),
                  timeline: open.timeline,
                  trackHeight: kTimelineStripTrackHeight,
                ),
        ),
      ],
    );
  }
}

class _StripHeader extends ConsumerWidget {
  const _StripHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(openTimelineProvider);

    return SizedBox(
      height: kTimelineStripHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.sm),
        child: Row(
          children: [
            Icon(
              Icons.timeline,
              size: 16,
              color: open == null ? colors.faint : colors.fern,
            ),
            const SizedBox(width: DsSpace.s),
            Expanded(
              child: Text(
                open?.timeline.title.isNotEmpty == true
                    ? open!.timeline.title
                    : 'Timeline',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: uiHeaderTextStyle(
                  size: 13,
                  weight: 600,
                  color: open == null ? colors.muted : colors.text,
                ),
              ),
            ),
            if (open != null)
              Text(
                open.timeline.items.length == 1
                    ? '1 entry'
                    : '${open.timeline.items.length} entries',
                style: uiTextStyle(size: 12, color: colors.muted),
              ),
          ],
        ),
      ),
    );
  }
}

class _NoTimeline extends StatelessWidget {
  const _NoTimeline();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'No timeline open. Choose one under Timelines, on the right.',
        style: uiTextStyle(size: 13, color: context.ds.faint),
      ),
    );
  }
}
