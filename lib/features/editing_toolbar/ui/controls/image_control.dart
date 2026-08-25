/// Inserts an image block after the focused paragraph.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';

class ImageControl extends StatelessWidget {
  const ImageControl({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ToolbarIconButton(
    icon: Icons.image,
    active: false,
    onPressed: onPressed,
    tooltip: 'Insert image',
  );
}
