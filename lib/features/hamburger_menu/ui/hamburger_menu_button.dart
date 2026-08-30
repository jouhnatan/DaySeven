/// The application's small, extensible hamburger menu.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

@immutable
class HamburgerMenuEntry {
  const HamburgerMenuEntry({required this.label, required this.onSelected})
    : checked = null;

  const HamburgerMenuEntry.action({
    required this.label,
    required this.onSelected,
  }) : checked = null;

  /// A reusable boolean menu item. A checked item carries its mark in the
  /// leading slot, and its label does not change weight — the mark is what
  /// says the item is on.
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
    final menu = DsDropdownMenuList<int>();
    for (var index = 0; index < entries.length; index++) {
      final entry = entries[index];
      menu.pushItem(
        key: entry.checked != null
            ? Key('hamburger-menu-toggle-$index')
            : null,
        value: index,
        label: entry.label,
        isChecked: entry.checked,
        leadingKey: entry.checked == true
            ? Key('hamburger-menu-toggle-check-$index')
            : null,
      );
    }

    final choice = await menu.show(context);
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
          semanticLabel: 'Menu',
          child: Icon(Icons.menu, size: 18, color: context.ds.text),
        ),
      ),
    );
  }
}
