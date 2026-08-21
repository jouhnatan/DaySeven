/// Shared visual primitive for compact editing-toolbar controls.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// Compact enough to keep the toolbar island comfortably proportioned.
const double kEditingToolbarIconSize = 14;

class ToolbarIconButton extends StatelessWidget {
  const ToolbarIconButton({
    required this.icon,
    required this.active,
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final button = DsButton(
      onPressed: onPressed,
      active: active,
      child: Icon(
        icon,
        size: kEditingToolbarIconSize,
        color: onPressed == null ? colors.muted : colors.text,
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
