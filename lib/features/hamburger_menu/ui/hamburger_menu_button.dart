/// The application's small, extensible hamburger menu.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

@immutable
class HamburgerMenuEntry {
  const HamburgerMenuEntry({required this.label, required this.onSelected})
    : checked = null;

  const HamburgerMenuEntry.action({
    required this.label,
    required this.onSelected,
  }) : checked = null;

  /// A reusable boolean menu item. Its label uses the menu's normal left edge
  /// while its checkmark occupies a trailing slot on the right.
  const HamburgerMenuEntry.toggle({
    required this.label,
    required this.checked,
    required this.onSelected,
  });

  final String label;
  final bool? checked;
  final VoidCallback onSelected;
}

class HamburgerMenuButton extends StatelessWidget {
  const HamburgerMenuButton({super.key, required this.entries});

  final List<HamburgerMenuEntry> entries;

  Future<void> _show(BuildContext context) async {
    final colors = context.ds;
    final choice = await showDsMenu<int>(
      context: context,
      items: [
        for (var index = 0; index < entries.length; index++)
          if (entries[index].checked case final checked?)
            DsMenuItem<int>(
              key: Key('hamburger-menu-toggle-$index'),
              value: index,
              height: kDsMenuItemHeight,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entries[index].label,
                      textAlign: TextAlign.left,
                      style: uiTextStyle(size: 13, color: colors.text),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    key: Key('hamburger-menu-toggle-indicator-$index'),
                    width: 16,
                    child: checked
                        ? Icon(
                            Icons.check,
                            key: Key('hamburger-menu-toggle-check-$index'),
                            size: 16,
                            color: colors.text,
                          )
                        : null,
                  ),
                ],
              ),
            )
          else
            DsMenuItem<int>(
              value: index,
              height: kDsMenuItemHeight,
              child: Text(
                entries[index].label,
                style: uiTextStyle(size: 13, color: colors.text),
              ),
            ),
      ],
    );
    if (choice == null || !context.mounted) return;
    entries[choice].onSelected();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Menu',
      child: SizedBox.square(
        key: const Key('hamburger-menu-button'),
        dimension: 34,
        child: DsButton(
          padding: EdgeInsets.zero,
          height: 34,
          highlight: context.ds.selection,
          onPressed: entries.isEmpty ? null : () => _show(context),
          child: Icon(Icons.menu, size: 18, color: context.ds.text),
        ),
      ),
    );
  }
}
