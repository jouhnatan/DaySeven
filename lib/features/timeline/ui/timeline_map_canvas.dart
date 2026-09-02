/// The centre of the Timelines view: where the map goes.
///
/// It is empty on purpose. The surface, its bounds and its place in the view
/// are settled here so that the map itself is the only thing left to add.
///
/// When a map image lands here, this surface gains a pin tool: a control that
/// arms pin-placement, a tap that writes a normalised `(x, y)` onto the
/// selected [TimelineItem], and a marker layer drawing one dot per item that
/// has coordinates — the white dot in the design. `TimelineItem` grows
/// `double? pinX, pinY` at that point, and the `.unearth` schema steps to
/// version 2. Those fields are deliberately absent from version 1 rather than
/// reserved: a schema should not carry a field nothing writes.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineMapCanvas extends StatelessWidget {
  const TimelineMapCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsPane(
      key: const Key('timeline-map-canvas'),
      editorSurface: true,
      child: Center(
        child: Text(
          'No map yet.',
          style: uiTextStyle(size: 13, color: colors.faint),
        ),
      ),
    );
  }
}
