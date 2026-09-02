/// The timeline itself, across the bottom of the Timelines view.
///
/// Closed it is a band carrying the track and nothing else, which is what the
/// view is for: the timeline is the constant, and the map and the reader above
/// it are what change as you move along it.
///
/// Expanded, the track moves up into the workspace and brings the inspector
/// with it — for when the work is editing the timeline rather than reading
/// from it. It takes the centre rather than floating over it, so there is only
/// ever one track on screen and only one of them has the scroll position.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/ui/timeline_inspector.dart';
import 'package:dayseven/features/timeline/ui/timeline_track.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// The height of the track in the closed band.
const double kTimelineStripTrackHeight = 132;

/// The band's own header row, which carries the name and the expand toggle.
const double kTimelineStripHeaderHeight = DsSize.smallControl + DsSpace.s;

/// The closed band across the bottom of the window.
class TimelineStrip extends ConsumerWidget {
  const TimelineStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openTimelineProvider);
    final expanded = ref.watch(stripExpandedProvider);

    return Column(
      key: const Key('timeline-strip'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StripHeader(),
        // While the track is expanded into the workspace, the band keeps only
        // its header: two tracks on screen would be two scroll positions
        // disagreeing about where you are.
        if (!expanded)
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

/// The track and its inspector, filling the workspace while expanded.
class TimelineFullView extends ConsumerWidget {
  const TimelineFullView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openTimelineProvider);

    return DsPane(
      key: const Key('timeline-full-view'),
      child: open == null
          ? const _NoTimeline()
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) => TimelineTrack(
                      key: ValueKey(open.relativePath),
                      timeline: open.timeline,
                      trackHeight: constraints.maxHeight,
                    ),
                  ),
                ),
                const DsSeam.horizontal(),
                const Padding(
                  padding: EdgeInsets.all(DsSpace.s),
                  child: TimelineInspector(),
                ),
              ],
            ),
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
            const TimelineStripExpandButton(),
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

/// The strip's expand toggle.
class TimelineStripExpandButton extends ConsumerWidget {
  const TimelineStripExpandButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final expanded = ref.watch(stripExpandedProvider);
    final hasTimeline = ref.watch(openTimelineProvider) != null;

    return Tooltip(
      message: expanded ? 'Retract timeline' : 'Expand timeline to full view',
      child: SizedBox.square(
        dimension: DsSize.smallControl,
        child: DsButton(
          key: const Key('timeline-strip-expand-button'),
          height: DsSize.smallControl,
          padding: EdgeInsets.zero,
          active: expanded,
          onPressed: !hasTimeline
              ? null
              : () =>
                    ref.read(stripExpandedProvider.notifier).state = !expanded,
          child: Icon(
            expanded ? Icons.close_fullscreen : Icons.open_in_full,
            size: 15,
            color: !hasTimeline
                ? colors.faint
                : expanded
                ? colors.onFern
                : colors.text,
          ),
        ),
      ),
    );
  }
}
