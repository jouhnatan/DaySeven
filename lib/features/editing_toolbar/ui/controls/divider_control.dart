/// Inserts a horizontal rule after the focused block.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';

class DividerControl extends StatelessWidget {
  const DividerControl({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ToolbarIconButton(
    icon: Icons.horizontal_rule,
    active: false,
    onPressed: onPressed,
    tooltip: 'Insert divider',
  );
}
