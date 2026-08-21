/// Shared positioning and chrome for popup menus.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/theme.dart';

const double kDsMenuItemHeight = 34;
const double kDsCompactMenuItemHeight = 32;
const double kDsMenuHeaderHeight = 30;
const double kDsMenuDividerSpacing = 7;
const double kDsMenuDividerHeight = kDsMenuDividerSpacing * 2 + 1;

/// A menu rule with equal breathing room above and below the line.
///
/// This keeps both the final item in one group and the first item in the next
/// from feeling crowded against the separator.
class DsMenuDivider extends PopupMenuEntry<Never> {
  const DsMenuDivider({super.key});

  @override
  double get height => kDsMenuDividerHeight;

  @override
  bool represents(void value) => false;

  @override
  State<DsMenuDivider> createState() => _DsMenuDividerState();
}

class _DsMenuDividerState extends State<DsMenuDivider> {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Align(
        alignment: Alignment.center,
        child: Divider(height: 1, thickness: 1, color: context.ds.border),
      ),
    );
  }
}

/// A popup-menu action with an inset, rounded highlight.
///
/// Keeping the inset inside each entry prevents hover and keyboard-focus fills
/// from running into the popup's outer corners.
class DsMenuItem<T> extends PopupMenuItem<T> {
  const DsMenuItem({
    super.key,
    super.value,
    super.onTap,
    super.enabled = true,
    super.height = kDsMenuItemHeight,
    super.padding,
    super.textStyle,
    super.labelTextStyle,
    super.mouseCursor,
    required super.child,
  });

  @override
  PopupMenuItemState<T, DsMenuItem<T>> createState() => _DsMenuItemState<T>();
}

class _DsMenuItemState<T> extends PopupMenuItemState<T, DsMenuItem<T>> {
  static const _inset = EdgeInsets.symmetric(horizontal: 6, vertical: 3);
  static const _contentPadding = EdgeInsets.symmetric(
    horizontal: 10,
    vertical: 4,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = context.ds;
    final enabled = widget.enabled;
    final states = <WidgetState>{if (!enabled) WidgetState.disabled};
    final style =
        widget.labelTextStyle?.resolve(states) ??
        widget.textStyle ??
        PopupMenuTheme.of(context).textStyle ??
        theme.textTheme.labelLarge ??
        const TextStyle();
    final contentHeight = widget.height > _inset.vertical
        ? widget.height - _inset.vertical
        : 0.0;

    Widget item = AnimatedDefaultTextStyle(
      style: style,
      duration: kThemeChangeDuration,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: contentHeight),
        child: Padding(
          padding: widget.padding ?? _contentPadding,
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: buildChild(),
          ),
        ),
      ),
    );

    if (!enabled) {
      item = IconTheme.merge(
        data: IconThemeData(
          opacity: theme.brightness == Brightness.dark ? 0.5 : 0.38,
        ),
        child: item,
      );
    }

    return MergeSemantics(
      child: buildSemantics(
        child: Padding(
          padding: _inset,
          child: InkWell(
            onTap: enabled ? handleTap : null,
            canRequestFocus: enabled,
            mouseCursor:
                widget.mouseCursor ??
                (enabled ? SystemMouseCursors.click : SystemMouseCursors.basic),
            borderRadius: const BorderRadius.all(DsRadius.menuItem),
            hoverDuration: DsMotion.hover,
            overlayColor: WidgetStateProperty.resolveWith((states) {
              if (!enabled) return Colors.transparent;
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused) ||
                  states.contains(WidgetState.pressed)) {
                return colors.buttonHighlight;
              }
              return Colors.transparent;
            }),
            child: item,
          ),
        ),
      ),
    );
  }
}

/// Shows a DaySeven menu below [context], or at the global pointer [position].
Future<T?> showDsMenu<T>({
  required BuildContext context,
  required List<PopupMenuEntry<T>> items,
  Offset? position,
}) {
  final anchor = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  if (anchor == null || overlay == null) return Future<T?>.value();

  final Rect rect;
  if (position case final point?) {
    final local = overlay.globalToLocal(point);
    rect = Rect.fromLTWH(local.dx, local.dy, 0, 0);
  } else {
    final topLeft = overlay.globalToLocal(anchor.localToGlobal(Offset.zero));
    final bottomRight = overlay.globalToLocal(
      anchor.localToGlobal(anchor.size.bottomRight(Offset.zero)),
    );
    rect = Rect.fromPoints(topLeft, bottomRight);
  }

  final colors = context.ds;
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
    color: colors.island,
    shape: RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(DsRadius.control),
      side: BorderSide(color: colors.border),
    ),
    items: items,
  );
}
