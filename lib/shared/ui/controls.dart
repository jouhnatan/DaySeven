/// Reusable interactive surfaces from the DaySeven visual language.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/theme.dart';

/// A feature-menu title drawn directly on the application background.
class DsMenuHeader extends StatelessWidget {
  const DsMenuHeader(this.label, {super.key}) : _visible = true;

  /// Reserves exactly the same vertical space as a menu header without
  /// drawing or announcing one. This keeps adjacent, untitled panes aligned
  /// with the menu surfaces below their headings.
  const DsMenuHeader.spacer({super.key}) : label = '\u00a0', _visible = false;

  final String label;
  final bool _visible;

  @override
  Widget build(BuildContext context) {
    final header = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: uiHeaderTextStyle(color: context.ds.text),
      ),
    );

    return _visible
        ? header
        : ExcludeSemantics(child: Opacity(opacity: 0, child: header));
  }
}

/// A rounded pane sitting on the application background.
class DsIsland extends StatelessWidget {
  const DsIsland({super.key, required this.child, this.editorSurface = false});

  final Widget child;
  final bool editorSurface;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      decoration: BoxDecoration(
        color: editorSurface ? colors.editorSurface : colors.island,
        borderRadius: const BorderRadius.all(DsRadius.island),
        border: Border.all(color: colors.surfaceOutline),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// A contrasting section nested inside an island.
///
/// Cards use the shared darker surface and can carry one horizontal separator
/// where they meet the island's primary content.
class DsCard extends StatelessWidget {
  const DsCard({super.key, required this.child, this.separator});

  final Widget child;
  final DsCardSeparator? separator;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final line = BorderSide(color: colors.border);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.cardSurface,
        border: switch (separator) {
          DsCardSeparator.top => Border(top: line),
          DsCardSeparator.bottom => Border(bottom: line),
          null => null,
        },
      ),
      child: child,
    );
  }
}

enum DsCardSeparator { top, bottom }

/// The bordered, focus-safe button used by the shell and feature controls.
///
/// It deliberately uses gestures rather than a Material button so clicking an
/// editor toolbar control does not steal the current text selection.
class DsButton extends StatefulWidget {
  const DsButton({
    super.key,
    required this.child,
    this.onPressed,
    this.active = false,
    this.highlight,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.borderRadius = const BorderRadius.all(DsRadius.control),
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool active;

  /// Overrides the theme's actionable-button highlight.
  final Color? highlight;
  final double? height;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  @override
  State<DsButton> createState() => _DsButtonState();
}

class _DsButtonState extends State<DsButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final enabled = widget.onPressed != null;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: DsMotion.hover,
          height: widget.height,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: (_hovered && enabled) || widget.active
                ? widget.highlight ?? colors.buttonHighlight
                : colors.island,
            borderRadius: widget.borderRadius,
            border: Border.all(color: colors.surfaceOutline),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// A text-only [DsButton], with typography and disabled colour kept uniform.
class DsLabelButton extends StatelessWidget {
  const DsLabelButton({
    super.key,
    required this.label,
    this.onPressed,
    this.highlight,
    this.horizontalPadding = 14,
    this.height = 34,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? highlight;
  final double horizontalPadding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsButton(
      onPressed: onPressed,
      highlight: highlight,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: uiTextStyle(
            size: 13,
            weight: 500,
            color: onPressed == null ? colors.muted : colors.text,
          ),
        ),
      ),
    );
  }
}

/// A clickable list/tree row with the shared actionable highlight treatment.
class DsHoverRow extends StatefulWidget {
  const DsHoverRow({
    super.key,
    required this.child,
    required this.onTap,
    this.selected = false,
    this.hoverOpacity = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool selected;
  final double hoverOpacity;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  State<DsHoverRow> createState() => _DsHoverRowState();
}

class _DsHoverRowState extends State<DsHoverRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final hovered = colors.buttonHighlight.withValues(
      alpha: widget.hoverOpacity,
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DsMotion.hover,
          margin: widget.margin,
          padding: widget.padding,
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.buttonHighlight
                : _hovered
                ? hovered
                : Colors.transparent,
            borderRadius: const BorderRadius.all(DsRadius.menuItem),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
