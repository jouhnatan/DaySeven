/// The centre of the Timelines view.
///
/// One slot showing whichever of three things is being looked at: the map, the
/// reader when it has been expanded over the map, or the timeline itself when
/// the strip has been expanded into full view. Only one thing is ever in the
/// centre, which is the same rule the shell applies to Editor and Differences.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/timeline/application/timeline_controller.dart';
import 'package:dayseven/features/timeline/ui/timeline_map_canvas.dart';
import 'package:dayseven/features/timeline/ui/timeline_reader_pane.dart';
import 'package:dayseven/features/timeline/ui/timeline_strip.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelinesWorkspace extends ConsumerWidget {
  const TimelinesWorkspace({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The timeline wins the centre over the reader: it is the larger gesture,
    // and the reader's own toggle is still on screen beside it to undo.
    if (ref.watch(stripExpandedProvider)) return const TimelineFullView();
    if (ref.watch(readerExpandedProvider)) return const _ExpandedReader();
    return const TimelineMapCanvas();
  }
}

/// The reader at full size, over the map.
class _ExpandedReader extends ConsumerWidget {
  const _ExpandedReader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DsPane(
      key: const Key('timeline-reader-expanded'),
      editorSurface: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DsSpace.sm,
              DsSpace.row,
              DsSpace.row,
              DsSpace.row,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Reading',
                    style: uiHeaderTextStyle(
                      size: 13,
                      weight: 600,
                      color: context.ds.muted,
                    ),
                  ),
                ),
                DsButton(
                  key: const Key('timeline-reader-retract-button'),
                  height: DsSize.smallControl,
                  padding: const EdgeInsets.symmetric(horizontal: DsSpace.gap),
                  onPressed: () =>
                      ref.read(readerExpandedProvider.notifier).state = false,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.close_fullscreen,
                        size: 14,
                        color: context.ds.text,
                      ),
                      const SizedBox(width: DsSpace.row),
                      Text(
                        'Retract',
                        style: uiTextStyle(
                          size: 12,
                          weight: 500,
                          color: context.ds.text,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const DsSeam.horizontal(),
          // Centred and held to a comfortable measure, the way the editor
          // holds its own text rather than letting it run the window's width.
          Expanded(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 780),
                child: const TimelineDescriptionPanel(expanded: true),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
