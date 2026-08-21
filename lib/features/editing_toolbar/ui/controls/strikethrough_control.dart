/// Strikethrough text modifier.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/text_modifier_button.dart';

class StrikethroughControl extends StatelessWidget {
  const StrikethroughControl({
    required this.active,
    required this.onPressed,
    super.key,
  });

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextModifierButton(
    format: EditingFormat.strikethrough,
    label: 'Strikethrough',
    icon: Icons.format_strikethrough,
    active: active,
    onPressed: onPressed,
  );
}
