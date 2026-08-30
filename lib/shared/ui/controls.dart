/// Reusable interactive surfaces from the DaySeven visual language.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dayseven/shared/ui/theme.dart';

/// A section title inside a pane, above the content it names.
///
/// Headings are the one place the slab serif appears. It labels a region; it
/// never carries a value or a control label. The header carries the seam that
/// separates it from its content, so the content below draws no edge of its
/// own.
class DsMenuHeader extends StatelessWidget {
  const DsMenuHeader(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      height: kDsSectionHeaderHeight,
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.sm),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.surfaceOutline)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: uiHeaderTextStyle(color: colors.text),
      ),
    );
  }
}

/// The height of a section header row inside a pane.
const double kDsSectionHeaderHeight = 32;

/// The single 1px line where two seated regions meet.
///
/// A seam is drawn once, by the join itself. Neither neighbour carries a
/// border of its own, so two regions never stack two lines where one belongs.
class DsSeam extends StatelessWidget {
  const DsSeam.horizontal({super.key}) : _vertical = false;
  const DsSeam.vertical({super.key}) : _vertical = true;

  final bool _vertical;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _vertical ? DsSpace.seam : null,
      height: _vertical ? null : DsSpace.seam,
      color: context.ds.surfaceOutline,
    );
  }
}

/// One region of the shell, seated against its neighbours.
///
/// Square and flat, by rule. A pane draws no edge of its own: the shell puts a
/// single 1px seam between two regions, and a pane that carried its own border
/// would double it. Depth is the seam, never a shadow.
class DsPane extends StatelessWidget {
  const DsPane({super.key, required this.child, this.editorSurface = false});

  final Widget child;
  final bool editorSurface;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      decoration: BoxDecoration(
        color: editorSurface ? colors.editorSurface : colors.island,
      ),
      clipBehavior: Clip.hardEdge,
      child: child,
    );
  }
}

/// A contrasting section nested inside a pane.
///
/// Cards use the recessed surface and can carry one hairline separator where
/// they meet the pane's primary content. A card inside a bordered surface does
/// not draw its own border — the system never doubles a border.
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

/// Draws the focus ring: 2px fern, offset 2px, matching the control's radius.
///
/// The ring is painted by a stack child positioned outside the bounds, so a
/// control that gains focus does not change size and nothing around it moves.
/// Focus is never removed, including for mouse users.
class DsFocusRing extends StatelessWidget {
  const DsFocusRing({
    super.key,
    required this.visible,
    required this.child,
    this.borderRadius = const BorderRadius.all(DsRadius.control),
  });

  final bool visible;
  final Widget child;
  final BorderRadiusGeometry borderRadius;

  @override
  Widget build(BuildContext context) {
    if (!visible) return child;

    const inset = DsSize.focusRingOffset + DsSize.focusRing;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned.fill(
          left: -inset,
          top: -inset,
          right: -inset,
          bottom: -inset,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(
                  color: context.ds.fern,
                  width: DsSize.focusRing,
                ),
                // The ring matches the control exactly. A square control gets a
                // square ring; only a pill grows its radius by the offset.
                borderRadius: borderRadius,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Which of the sanctioned button treatments a [DsButton] wears.
///
/// There is one primary action per surface. If a second button on screen is
/// filled with fern, one of the two is wrong.
enum DsButtonVariant {
  /// An ink label on nothing, washed on hover. The default, and most buttons.
  secondary,

  /// Fern fill, cream label, no border. The action that commits.
  primary,

  /// The same as [secondary] with no hover fill of its own to override. For a
  /// command that must not compete.
  quiet,

  /// A danger label on nothing, washed with the removal tint on hover.
  /// Destructive commands are never filled with fern; a filled destructive
  /// button belongs only in the confirmation dialog that follows.
  danger,
}

/// The frameless, focus-safe button used by the shell and feature controls.
///
/// A button carries no edge of its own: the label or icon is the target, and a
/// wash says it is under the pointer. Only the primary action is filled. Set
/// [framed] where a control genuinely reads as a box — a field-adjacent
/// affordance — rather than as a command.
///
/// It deliberately uses gestures rather than a Material button so clicking an
/// editor toolbar control does not steal the current text selection. It is
/// still reachable and operable from the keyboard: the editing toolbar opts
/// its own copies out of the focus traversal instead.
///
/// [active] is a *state*, not a hover — a mode that is switched on. It fills
/// with fern and stands out until it is switched off again.
class DsButton extends StatefulWidget {
  const DsButton({
    super.key,
    required this.child,
    this.onPressed,
    this.active = false,
    this.variant = DsButtonVariant.secondary,
    this.highlight,
    this.height,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.borderRadius = const BorderRadius.all(DsRadius.control),
    this.framed = false,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final bool active;
  final DsButtonVariant variant;

  /// Overrides the fill this button takes while hovered.
  final Color? highlight;
  final double? height;

  /// Names the action for assistive technology. Required in practice for an
  /// icon-only button, which has no text to read.
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final BorderRadiusGeometry borderRadius;

  /// Draws the 1px object edge a button normally goes without. For the rare
  /// control that has to read as a box beside a field, never for a command.
  final bool framed;

  @override
  State<DsButton> createState() => _DsButtonState();
}

class _DsButtonState extends State<DsButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  void _activate() => widget.onPressed?.call();

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final enabled = widget.onPressed != null;
    final active = widget.active;

    final filled = active || widget.variant == DsButtonVariant.primary;
    final destructive = widget.variant == DsButtonVariant.danger;
    final quiet = widget.variant == DsButtonVariant.quiet;
    final label = destructive ? colors.danger : colors.text;

    // An unframed button shows no edge in any state; the wash is what says it
    // is under the pointer. Only [DsButton.framed] asks for one back.
    final frame = widget.framed ? colors.surfaceOutline : Colors.transparent;

    final (Color fill, Color edge, Color foreground) = switch (null) {
      // Disabled fills with the recessed surface rather than fading: there is
      // no translucency anywhere in this interface.
      _ when !enabled => (
        filled ? colors.cardSurface : Colors.transparent,
        filled ? colors.cardSurface : frame,
        colors.faint,
      ),
      _ when filled => (
        _hovered || _pressed ? colors.fernHover : colors.fern,
        _hovered || _pressed ? colors.fernHover : colors.fern,
        colors.onFern,
      ),
      _ when _pressed => (colors.pressed, frame, label),
      _ when _hovered => (
        quiet
            ? colors.hover
            : destructive
            ? colors.removal
            : widget.highlight ?? colors.hover,
        frame,
        label,
      ),
      _ => (Colors.transparent, frame, label),
    };

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      child: Focus(
        canRequestFocus: enabled,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (!enabled || event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.space) {
            return KeyEventResult.ignored;
          }
          _activate();
          return KeyEventResult.handled;
        },
        // Hover is tracked directly rather than through the focus system.
        // A pointer entering a control is not a question about highlight
        // policy, and routing it through one silently loses the hover state
        // wherever the framework decides highlights are not being shown.
        child: MouseRegion(
          cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: DsFocusRing(
            visible: _focused && enabled,
            borderRadius: widget.borderRadius,
            child: GestureDetector(
              onTap: widget.onPressed,
              onTapDown: enabled
                  ? (_) => setState(() => _pressed = true)
                  : null,
              onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
              onTapCancel: enabled
                  ? () => setState(() => _pressed = false)
                  : null,
              child: AnimatedContainer(
                duration: DsMotion.of(context, DsMotion.hover),
                curve: DsMotion.curve,
                height: widget.height,
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: widget.borderRadius,
                  border: Border.all(color: edge),
                ),
                // Children that state their own colour keep it; those that do
                // not follow the button, so a toggled-on button reads correctly
                // without every caller restating it.
                child: Center(
                  widthFactor: 1,
                  heightFactor: 1,
                  child: IconTheme.merge(
                    data: IconThemeData(color: foreground),
                    child: DefaultTextStyle.merge(
                      style: TextStyle(color: foreground),
                      child: widget.child,
                    ),
                  ),
                ),
              ),
            ),
          ),
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
    this.active = false,
    this.variant = DsButtonVariant.secondary,
    this.horizontalPadding = 14,
    this.height = 34,
  });

  final String label;
  final VoidCallback? onPressed;
  final Color? highlight;
  final bool active;
  final DsButtonVariant variant;
  final double horizontalPadding;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsButton(
      onPressed: onPressed,
      highlight: highlight,
      active: active,
      variant: variant,
      height: height,
      semanticLabel: label,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: Center(
        widthFactor: 1,
        child: Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: uiTextStyle(
            size: 13,
            weight: 500,
            color: onPressed == null
                ? colors.faint
                : active || variant == DsButtonVariant.primary
                ? colors.onFern
                : variant == DsButtonVariant.danger
                ? colors.danger
                : colors.text,
          ),
        ),
      ),
    );
  }
}

/// A clickable list or navigation row.
///
/// [selected] means *this is where you are*, so it fills solid rather than
/// washing: position is shown by fill, not by weight. Hover is the neutral
/// wash every surface shares.
class DsHoverRow extends StatefulWidget {
  const DsHoverRow({
    super.key,
    required this.child,
    required this.onTap,
    this.selected = false,
    this.hoverOpacity = 1,
    this.semanticLabel,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final VoidCallback onTap;
  final bool selected;
  final double hoverOpacity;
  final String? semanticLabel;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  State<DsHoverRow> createState() => _DsHoverRowState();
}

class _DsHoverRowState extends State<DsHoverRow> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final foreground = widget.selected ? colors.onNavSelected : colors.text;

    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey != LogicalKeyboardKey.enter &&
              event.logicalKey != LogicalKeyboardKey.space) {
            return KeyEventResult.ignored;
          }
          widget.onTap();
          return KeyEventResult.handled;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: DsFocusRing(
            visible: _focused,
            borderRadius: const BorderRadius.all(DsRadius.row),
            child: GestureDetector(
              onTap: widget.onTap,
              child: AnimatedContainer(
                duration: DsMotion.of(context, DsMotion.hover),
                curve: DsMotion.curve,
                margin: widget.margin,
                padding: widget.padding,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? colors.navSelected
                      : _hovered
                      ? colors.hover.withValues(
                          alpha: colors.hover.a * widget.hoverOpacity,
                        )
                      : Colors.transparent,
                  borderRadius: const BorderRadius.all(DsRadius.row),
                ),
                child: IconTheme.merge(
                  data: IconThemeData(color: foreground),
                  child: DefaultTextStyle.merge(
                    style: TextStyle(color: foreground),
                    child: widget.child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of two to four exclusive options, all of them worth showing.
///
/// A framed strip on the recessed surface, with the chosen cell raised out of
/// it in paper. Selection here is not fern: these are settings rather than
/// places, and the accent is reserved for where you are and for what commits.
/// Five or more options belong in a menu instead.
class DsSegmented<T> extends StatelessWidget {
  const DsSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onPick,
    this.cellHeight = 30,
  });

  final T value;

  /// The height of a cell. The strip itself stands 6px taller: two for its
  /// inner padding and one for its border, on each edge. Set it so the strip
  /// matches the height of the controls it sits beside — a segmented control
  /// that is two pixels taller than its neighbours makes the whole row look
  /// misaligned.
  final double cellHeight;

  /// Each cell, in the order they are shown. [DsSegmentedOption.semanticLabel]
  /// names the cell for assistive technology and for its tooltip, which an
  /// icon-only cell has no text to supply.
  final List<DsSegmentedOption<T>> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final option in options)
            _DsSegmentedCell(
              option: option,
              selected: option.value == value,
              height: cellHeight,
              onPick: () => onPick(option.value),
            ),
        ],
      ),
    );
  }
}

@immutable
class DsSegmentedOption<T> {
  const DsSegmentedOption({
    required this.value,
    required this.child,
    required this.semanticLabel,
  });

  final T value;
  final Widget child;
  final String semanticLabel;
}

class _DsSegmentedCell<T> extends StatefulWidget {
  const _DsSegmentedCell({
    required this.option,
    required this.selected,
    required this.height,
    required this.onPick,
  });

  final DsSegmentedOption<T> option;
  final bool selected;
  final double height;
  final VoidCallback onPick;

  @override
  State<_DsSegmentedCell<T>> createState() => _DsSegmentedCellState<T>();
}

class _DsSegmentedCellState<T> extends State<_DsSegmentedCell<T>> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final selected = widget.selected;

    return Semantics(
      button: true,
      selected: selected,
      label: widget.option.semanticLabel,
      child: Tooltip(
        message: widget.option.semanticLabel,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: widget.onPick,
            child: AnimatedContainer(
              duration: DsMotion.of(context, DsMotion.hover),
              curve: DsMotion.curve,
              height: widget.height,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? colors.island
                    : _hovered
                    ? colors.hover
                    : Colors.transparent,
                borderRadius: const BorderRadius.all(DsRadius.row),
                // The chosen cell is lifted out of the strip. This is the one
                // shadow in the system that is not on something floating above
                // the page: without it, paper on the recessed surface is too
                // fine a distinction to read as "this is the one".
                boxShadow: selected ? cfSegmentedShadow : null,
              ),
              child: IconTheme.merge(
                data: IconThemeData(
                  color: selected ? colors.text : colors.muted,
                ),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    color: selected ? colors.text : colors.muted,
                  ),
                  child: widget.option.child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// What a semantic mark means. The colour describes a state; it is never an
/// accent, and it never fills a block larger than a chip.
enum DsTone { neutral, success, warning, danger }

extension _DsToneColor on DsTone {
  Color of(DsColors colors) => switch (this) {
    DsTone.neutral => colors.muted,
    DsTone.success => colors.success,
    DsTone.warning => colors.pending,
    DsTone.danger => colors.danger,
  };
}

/// The state of something, as a fact with a time.
///
/// A bare status word goes stale without saying so, which is why the sub-line
/// is not optional: "Up to date" is only true as of when it was last checked,
/// so it carries "Checked today at 9:14 AM" underneath it.
class DsStatusBlock extends StatelessWidget {
  const DsStatusBlock({
    super.key,
    required this.icon,
    required this.headline,
    required this.detail,
    this.tone = DsTone.neutral,
    this.trailing,
  });

  final IconData icon;
  final String headline;

  /// When this was last true. A state that can go stale says when it was
  /// established.
  final String detail;
  final DsTone tone;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 19, color: tone.of(colors)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(headline, style: DsType.bodyStrong()),
                Text(detail, style: DsType.caption(color: colors.muted)),
              ],
            ),
          ),
          if (trailing case final trailing?) ...[
            const SizedBox(width: 12),
            trailing,
          ],
        ],
      ),
    );
  }
}

/// A label, an optional one-line helper beneath it, and the control that
/// changes it — the single most repeated composition in the product.
///
/// Labels left, values right. If the helper needs a second line, the label is
/// wrong rather than the helper.
class DsSettingRow extends StatelessWidget {
  const DsSettingRow({
    super.key,
    required this.label,
    required this.trailing,
    this.helper,
    this.first = false,
  });

  final String label;
  final String? helper;
  final Widget trailing;

  /// The first row in a group draws no rule above it; the surface's own edge
  /// is already there, and the system never doubles a line.
  final bool first;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: first
          ? null
          : BoxDecoration(
              border: Border(top: BorderSide(color: colors.border)),
            ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: DsType.body()),
                if (helper case final helper?)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      helper,
                      // Helper lines carry builds, counts, sizes and times
                      // more often than not, and tabular figures change
                      // nothing for a line with no digits in it.
                      style: DsType.caption(color: colors.muted, tabular: true),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          trailing,
        ],
      ),
    );
  }
}
