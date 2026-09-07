/// Adds or removes paragraph spacing before the focused block.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';

class ParagraphSpacingControl extends StatelessWidget {
  const ParagraphSpacingControl({
    required this.hasSpaceBefore,
    required this.onPressed,
    super.key,
  });

  final bool hasSpaceBefore;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return ToolbarIconButton(
      icon: Icons.format_line_spacing,
      active: hasSpaceBefore,
      tooltip: hasSpaceBefore
          ? 'Remove space before paragraph'
          : 'Add space before paragraph',
      onPressed: onPressed,
    );
  }
}
