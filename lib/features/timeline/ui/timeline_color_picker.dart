/// A color picker dropdown button for timeline milestone items and duration periods.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

class TimelineColorPicker extends StatelessWidget {
  const TimelineColorPicker({
    super.key,
    required this.selectedColor,
    required this.onColorSelected,
  });

  final TimelineColor selectedColor;
  final ValueChanged<TimelineColor> onColorSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return PopupMenuButton<TimelineColor>(
      tooltip: 'Item Color: ${selectedColor.label}',
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
                border: Border.all(
                  color: colors.surfaceOutline,
                  width: 1.5,
                ),
              ),
            ),
            trailing: c == selectedColor
                ? Icon(
                    Icons.check,
                    size: 14,
                    color: colors.fern,
                  )
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
                border: Border.all(
                  color: colors.surfaceOutline,
                  width: 1,
                ),
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_drop_down,
              size: 14,
              color: colors.muted,
            ),
          ],
        ),
      ),
    );
  }
}
