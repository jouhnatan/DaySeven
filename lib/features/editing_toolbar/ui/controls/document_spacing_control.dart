/// File-wide distance between document blocks.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';

class DocumentSpacingControl extends StatelessWidget {
  const DocumentSpacingControl({
    required this.spacing,
    required this.onPick,
    super.key,
  });

  final double spacing;
  final ValueChanged<double> onPick;

  @override
  Widget build(BuildContext context) {
    return ToolbarIconButton(
      icon: Icons.format_line_spacing,
      active: spacing != kDefaultBlockSpacing,
      tooltip: 'Block spacing (${_label(spacing)})',
      onPressed: () async {
        final menu = DsDropdownMenuList<double>();
        for (final value in kBlockSpacingPresets) {
          menu.pushItem(
            value: value,
            label: switch (value) {
              1 => 'Single',
              2 => 'Double',
              _ => _label(value),
            },
            height: kDsCompactMenuItemHeight,
          );
        }
        final picked = await menu.show(context);
        if (picked != null) onPick(picked);
      },
    );
  }

  static String _label(double value) =>
      value == value.roundToDouble() ? value.toInt().toString() : '$value';
}
