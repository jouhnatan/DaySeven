/// Opens the curated special-character picker.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';

class SpecialCharacterControl extends StatelessWidget {
  const SpecialCharacterControl({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ToolbarIconButton(
    icon: Icons.emoji_symbols_outlined,
    active: false,
    onPressed: onPressed,
    tooltip: 'Insert special character',
  );
}
