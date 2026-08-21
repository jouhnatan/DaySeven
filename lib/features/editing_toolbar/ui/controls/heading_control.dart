/// Body-text and heading-level chooser.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/features/editing_toolbar/ui/controls/toolbar_icon_button.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

class HeadingControl extends StatelessWidget {
  const HeadingControl({required this.level, required this.onPick, super.key});

  final int? level;
  final ValueChanged<int?> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsButton(
      active: level != null,
      onPressed: () async {
        // Zero means body text because null is reserved for menu dismissal.
        final picked = await showDsMenu<int>(
          context: context,
          items: [
            for (final (value, label) in const <(int, String)>[
              (0, 'Body text'),
              (1, 'Heading 1'),
              (2, 'Heading 2'),
              (3, 'Heading 3'),
              (4, 'Heading 4'),
            ])
              DsMenuItem<int>(
                value: value,
                height: kDsCompactMenuItemHeight,
                child: Text(
                  label,
                  style: uiTextStyle(
                    size: 13,
                    weight: value == (level ?? 0) ? 600 : 400,
                    color: colors.text,
                  ),
                ),
              ),
          ],
        );

        if (picked != null) onPick(picked == 0 ? null : picked);
      },
      child: SizedBox(
        width: kEditingToolbarIconSize,
        height: kEditingToolbarIconSize,
        child: Center(
          child: level == null
              ? Icon(
                  Icons.title,
                  size: kEditingToolbarIconSize,
                  color: colors.text,
                )
              : FittedBox(
                  child: Text(
                    'H$level',
                    style: uiTextStyle(
                      size: 11,
                      weight: 600,
                      color: colors.text,
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}
