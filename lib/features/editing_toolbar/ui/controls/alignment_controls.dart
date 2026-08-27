/// Block-alignment controls.
///
/// Three exclusive options, all worth showing, so they are one framed strip
/// rather than three buttons that happen to be mutually exclusive. It also
/// keeps the toolbar from carrying a permanently fern-filled control: a block
/// always has an alignment, so a toggled-on button here would never be off.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/controls.dart';

class AlignmentControls extends StatelessWidget {
  const AlignmentControls({
    required this.align,
    required this.onPick,
    super.key,
  });

  final BlockAlign align;
  final ValueChanged<BlockAlign> onPick;

  @override
  Widget build(BuildContext context) => DsSegmented<BlockAlign>(
    value: align,
    onPick: onPick,
    // Sized so the strip stands exactly as tall as the framed buttons on
    // either side of it.
    cellHeight: 28,
    options: const [
      DsSegmentedOption(
        value: BlockAlign.left,
        semanticLabel: 'Align left',
        child: Icon(Icons.format_align_left, size: kEditingToolbarIconSize),
      ),
      DsSegmentedOption(
        value: BlockAlign.center,
        semanticLabel: 'Align centre',
        child: Icon(Icons.format_align_center, size: kEditingToolbarIconSize),
      ),
      DsSegmentedOption(
        value: BlockAlign.right,
        semanticLabel: 'Align right',
        child: Icon(Icons.format_align_right, size: kEditingToolbarIconSize),
      ),
    ],
  );
}
