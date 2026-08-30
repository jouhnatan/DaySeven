/// Common behavior for an inline text-modifier control.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/core/keybinds/data/keybind_hash_map.dart';
import 'package:dayseven/core/keybinds/domain/keybind_action.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';

class TextModifierButton extends StatelessWidget {
  const TextModifierButton({
    required this.format,
    required this.label,
    required this.icon,
    required this.active,
    required this.onPressed,
    super.key,
  });

  final EditingFormat format;
  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final action = KeybindAction.fromEditingFormat(format);
    final tooltip = KeybindHashMap.instance.getTooltipText(
      action,
      defaultTargetPlatform,
      customLabel: label,
    );
    return ToolbarIconButton(
      icon: icon,
      active: active,
      onPressed: onPressed,
      tooltip: tooltip,
    );
  }
}
