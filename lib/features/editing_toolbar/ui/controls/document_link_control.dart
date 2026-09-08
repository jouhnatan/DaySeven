/// Opens the document picker and inserts an internal page link.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';

class DocumentLinkControl extends StatelessWidget {
  const DocumentLinkControl({required this.onPressed, super.key});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => ToolbarIconButton(
    icon: Icons.description_outlined,
    active: false,
    onPressed: onPressed,
    tooltip: 'Link to page',
  );
}
