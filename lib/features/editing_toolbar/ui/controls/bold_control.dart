/// Bold text modifier.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/text_modifier_button.dart';

class BoldControl extends StatelessWidget {
  const BoldControl({required this.active, required this.onPressed, super.key});

  final bool active;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextModifierButton(
    format: EditingFormat.bold,
    label: 'Bold',
    icon: Icons.format_bold,
    active: active,
    onPressed: onPressed,
  );
}
