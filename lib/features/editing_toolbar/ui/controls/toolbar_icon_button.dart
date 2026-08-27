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
      semanticLabel: tooltip,
      child: Icon(
        icon,
        size: kEditingToolbarIconSize,
        // A toggled-on control is a fern block, so its glyph has to be the
        // cream that goes on fern rather than ink.
        color: onPressed == null
            ? colors.faint
            : active
            ? colors.onFern
            : colors.text,
      ),
    );

    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}
