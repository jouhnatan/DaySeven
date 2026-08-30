/// Configurable dropdown menu list structure and items.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

export 'package:dayseven/shared/ui/menu.dart'
    show kDsMenuItemHeight, kDsCompactMenuItemHeight, kDsMenuHeaderHeight;

/// The placement of an icon relative to the label in a dropdown menu item.
enum DsDropdownIconPosition {
  /// Icon is placed to the left of the item text.
  leading,

  /// Icon is placed to the right of the item text.
  trailing,
}

/// Abstract base entry in a dropdown menu list.
sealed class DsDropdownMenuEntry<T> {
  const DsDropdownMenuEntry();

  /// Builds the corresponding Flutter [PopupMenuEntry] widget for this entry.
  PopupMenuEntry<T> build(BuildContext context);
}

/// A selectable item in a dropdown menu.
class DsDropdownMenuItem<T> extends DsDropdownMenuEntry<T> {
  const DsDropdownMenuItem({
    required this.label,
    this.value,
    this.icon,
    this.iconPosition = DsDropdownIconPosition.leading,
    this.leading,
    this.trailing,
    this.textStyle,
    this.tooltip,
    this.onTap,
    this.enabled = true,
    this.isDestructive = false,
    this.isChecked,
    this.height = kDsMenuItemHeight,
    this.shortcut,
    this.key,
    this.leadingKey,
    this.trailingKey,
  });

  final Key? key;
  final Key? leadingKey;
  final Key? trailingKey;
  final String label;
  final T? value;
  final Widget? icon;
  final DsDropdownIconPosition iconPosition;
  final Widget? leading;
  final Widget? trailing;
  final TextStyle? textStyle;
  final String? tooltip;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isDestructive;
  final bool? isChecked;
  final double height;
  final String? shortcut;

  @override
  PopupMenuEntry<T> build(BuildContext context) {
    final colors = context.ds;

    final Color textColor = switch ((enabled, isDestructive)) {
      (false, _) => colors.muted,
      (true, true) => colors.danger,
      (true, false) => colors.text,
    };

    final TextStyle labelStyle = textStyle ??
        uiTextStyle(
          size: 13,
          color: textColor,
        );

    Widget? leadingSlot = leading;
    Widget? trailingSlot = trailing;

    if (leadingSlot == null) {
      if (isChecked != null) {
        leadingSlot = SizedBox(
          width: 16,
          child: isChecked!
              ? Icon(
                  Icons.check,
                  key: leadingKey,
                  size: 14,
                  color: colors.fern,
                )
              : null,
        );
      } else if (icon != null && iconPosition == DsDropdownIconPosition.leading) {
        leadingSlot = IconTheme.merge(
          data: IconThemeData(
            size: 16,
            color: isDestructive ? colors.danger : colors.muted,
          ),
          child: leadingKey != null
              ? KeyedSubtree(key: leadingKey, child: icon!)
              : icon!,
        );
      }
    }

    if (trailingSlot == null) {
      if (icon != null && iconPosition == DsDropdownIconPosition.trailing) {
        trailingSlot = IconTheme.merge(
          data: IconThemeData(
            size: 16,
            color: isDestructive ? colors.danger : colors.muted,
          ),
          child: trailingKey != null
              ? KeyedSubtree(key: trailingKey, child: icon!)
              : icon!,
        );
      }
    }

    Widget labelContent = Text(
      label,
      style: labelStyle,
      overflow: TextOverflow.ellipsis,
    );
    if (tooltip != null) {
      labelContent = Tooltip(
        message: tooltip!,
        child: labelContent,
      );
    }

    return DsMenuItem<T>(
      key: key,
      value: value,
      onTap: onTap,
      enabled: enabled,
      height: height,
      child: Row(
        children: [
          if (leadingSlot != null) ...[
            leadingSlot,
            const SizedBox(width: 8),
          ],
          Expanded(
            child: labelContent,
          ),
          if (shortcut != null) ...[
            const SizedBox(width: 8),
            Text(
              shortcut!,
              style: uiTextStyle(size: 11, color: colors.muted),
            ),
          ],
          if (trailingSlot != null) ...[
            const SizedBox(width: 8),
            trailingSlot,
          ],
        ],
      ),
    );
  }
}

/// A horizontal divider bar in a dropdown menu.
class DsDropdownMenuDivider<T> extends DsDropdownMenuEntry<T> {
  const DsDropdownMenuDivider({this.key});

  final Key? key;

  @override
  PopupMenuEntry<T> build(BuildContext context) => DsMenuDivider(key: key);
}

/// A non-actionable section header in a dropdown menu.
class DsDropdownMenuHeader<T> extends DsDropdownMenuEntry<T> {
  const DsDropdownMenuHeader({
    required this.text,
    this.key,
  });

  final Key? key;
  final String text;

  @override
  PopupMenuEntry<T> build(BuildContext context) {
    return DsMenuItem<T>(
      key: key,
      enabled: false,
      height: kDsMenuHeaderHeight,
      child: Text(
        text,
        style: uiTextStyle(size: 12, color: context.ds.muted),
      ),
    );
  }
}

/// A custom widget entry in a dropdown menu.
class DsDropdownMenuCustom<T> extends DsDropdownMenuEntry<T> {
  const DsDropdownMenuCustom({
    required this.child,
    this.value,
    this.enabled = true,
    this.height = kDsMenuItemHeight,
    this.padding,
    this.key,
  });

  final Key? key;
  final Widget child;
  final T? value;
  final bool enabled;
  final double height;
  final EdgeInsets? padding;

  @override
  PopupMenuEntry<T> build(BuildContext context) {
    return PopupMenuItem<T>(
      key: key,
      value: value,
      enabled: enabled,
      height: height,
      padding: padding ?? const EdgeInsets.symmetric(horizontal: 12),
      child: child,
    );
  }
}

/// A configurable list structure representing a dropdown menu.
///
/// Supports stack operations [push] and [pop], index access, and builds
/// into a list of [PopupMenuEntry] widgets for [showDsMenu] or [PopupMenuButton].
class DsDropdownMenuList<T> {
  DsDropdownMenuList([List<DsDropdownMenuEntry<T>>? initialEntries])
      : _entries = initialEntries != null ? List.of(initialEntries) : [];

  final List<DsDropdownMenuEntry<T>> _entries;

  /// Number of entries in the menu list.
  int get length => _entries.length;

  /// Whether the menu list contains no entries.
  bool get isEmpty => _entries.isEmpty;

  /// Whether the menu list contains at least one entry.
  bool get isNotEmpty => _entries.isNotEmpty;

  /// Pushes a new entry to the end of the menu list.
  void push(DsDropdownMenuEntry<T> entry) => _entries.add(entry);

  /// Pushes multiple entries to the end of the menu list.
  void pushAll(Iterable<DsDropdownMenuEntry<T>> entries) =>
      _entries.addAll(entries);

  /// Pushes a selectable item to the end of the menu list.
  void pushItem({
    required String label,
    T? value,
    Widget? icon,
    DsDropdownIconPosition iconPosition = DsDropdownIconPosition.leading,
    Widget? leading,
    Widget? trailing,
    TextStyle? textStyle,
    String? tooltip,
    VoidCallback? onTap,
    bool enabled = true,
    bool isDestructive = false,
    bool? isChecked,
    double height = kDsMenuItemHeight,
    String? shortcut,
    Key? key,
    Key? leadingKey,
    Key? trailingKey,
  }) {
    _entries.add(
      DsDropdownMenuItem<T>(
        key: key,
        leadingKey: leadingKey,
        trailingKey: trailingKey,
        label: label,
        value: value,
        icon: icon,
        iconPosition: iconPosition,
        leading: leading,
        trailing: trailing,
        textStyle: textStyle,
        tooltip: tooltip,
        onTap: onTap,
        enabled: enabled,
        isDestructive: isDestructive,
        isChecked: isChecked,
        height: height,
        shortcut: shortcut,
      ),
    );
  }

  /// Pushes a custom widget entry to the end of the menu list.
  void pushCustom(
    Widget child, {
    T? value,
    bool enabled = true,
    double height = kDsMenuItemHeight,
    EdgeInsets? padding,
    Key? key,
  }) {
    _entries.add(
      DsDropdownMenuCustom<T>(
        key: key,
        value: value,
        enabled: enabled,
        height: height,
        padding: padding,
        child: child,
      ),
    );
  }

  /// Pushes a horizontal divider bar to the end of the menu list.
  void pushDivider({Key? key}) {
    _entries.add(DsDropdownMenuDivider<T>(key: key));
  }

  /// Pushes a non-actionable section header to the end of the menu list.
  void pushHeader({required String text, Key? key}) {
    _entries.add(DsDropdownMenuHeader<T>(text: text, key: key));
  }

  /// Pops and returns the last entry from the menu list, or `null` if empty.
  DsDropdownMenuEntry<T>? pop() {
    if (_entries.isEmpty) return null;
    return _entries.removeLast();
  }

  /// Clears all entries from the menu list.
  void clear() => _entries.clear();

  /// Accesses the entry at [index].
  DsDropdownMenuEntry<T> operator [](int index) => _entries[index];

  /// Replaces the entry at [index].
  void operator []=(int index, DsDropdownMenuEntry<T> value) =>
      _entries[index] = value;

  /// Removes and returns the entry at [index].
  DsDropdownMenuEntry<T> removeAt(int index) => _entries.removeAt(index);

  /// Inserts an entry at [index].
  void insert(int index, DsDropdownMenuEntry<T> entry) =>
      _entries.insert(index, entry);

  /// An unmodifiable view of the entries currently in the list.
  List<DsDropdownMenuEntry<T>> get entries => List.unmodifiable(_entries);

  /// Builds the menu entries into Flutter [PopupMenuEntry] widgets.
  List<PopupMenuEntry<T>> build(BuildContext context) {
    return _entries.map((entry) => entry.build(context)).toList();
  }

  /// Displays this dropdown menu below [context] or at [position].
  Future<T?> show(BuildContext context, {Offset? position}) {
    return showDsMenu<T>(
      context: context,
      items: build(context),
      position: position,
    );
  }
}
