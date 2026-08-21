/// Block-alignment controls.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';

class AlignmentControls extends StatelessWidget {
  const AlignmentControls({
    required this.align,
    required this.onPick,
    super.key,
  });

  final BlockAlign align;
  final ValueChanged<BlockAlign> onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      for (final (value, icon) in const [
        (BlockAlign.left, Icons.format_align_left),
        (BlockAlign.center, Icons.format_align_center),
        (BlockAlign.right, Icons.format_align_right),
      ]) ...[
        ToolbarIconButton(
          icon: icon,
          active: align == value,
          onPressed: () => onPick(value),
        ),
        if (value != BlockAlign.right)
          const SizedBox(width: DsSpace.controlGap),
      ],
    ],
  );
}
