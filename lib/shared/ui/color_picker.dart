/// A colour picker dropdown for anything the user can colour: timeline items,
/// nations, person types and resource types.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DsColorPicker extends StatelessWidget {
  const DsColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
    this.tooltipPrefix = 'Colour',
  });

  final TimelineColor selectedColor;
  final ValueChanged<TimelineColor> onColorSelected;

  /// Names what is being coloured, so the tooltip reads naturally wherever the
  /// picker is used.
  final String tooltipPrefix;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return PopupMenuButton<TimelineColor>(
      tooltip: '$tooltipPrefix: ${selectedColor.label}',
      popUpAnimationStyle: AnimationStyle.noAnimation,
      initialValue: selectedColor,
      onSelected: onColorSelected,
      offset: const Offset(0, 36),
      color: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.menu),
        side: BorderSide(color: colors.surfaceOutline),
      ),
      itemBuilder: (context) {
        final menu = DsDropdownMenuList<TimelineColor>();
        for (final c in TimelineColor.values) {
          menu.pushItem(
            value: c,
            label: c.label,
            textStyle: uiTextStyle(
              size: 12,
              weight: c == selectedColor ? 600 : 400,
              color: colors.text,
            ),
            leading: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: c.color,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surfaceOutline, width: 1.5),
              ),
            ),
            trailing: c == selectedColor
                ? Icon(Icons.check, size: 14, color: colors.fern)
                : null,
          );
        }
        return menu.build(context);
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: colors.island,
          borderRadius: const BorderRadius.all(DsRadius.control),
          border: Border.all(color: colors.surfaceOutline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: selectedColor.color,
                shape: BoxShape.circle,
                border: Border.all(color: colors.surfaceOutline, width: 1),
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.arrow_drop_down, size: 14, color: colors.muted),
          ],
        ),
      ),
    );
  }
}
