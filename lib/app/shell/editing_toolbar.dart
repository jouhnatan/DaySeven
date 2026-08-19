/// The formatting toolbar, in the bottom bar beside Differences.
///
/// It sits outside the editor's widget tree, so everything it knows comes from
/// [editingFocusProvider] and everything it does goes back through the same
/// controller. See `editing_focus.dart` for why the channel is shaped that way.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// Small enough that Differences stays the tallest thing in the bottom bar,
/// which two shell tests measure their spacing from.
const double _kIconSize = 14;

class EditingToolbar extends ConsumerWidget {
  const EditingToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(editingFocusProvider);
    final notifier = ref.read(editingFocusProvider.notifier);

    // Nothing to format until the caret is in a block.
    if (focus == null) return const SizedBox.shrink();

    // Inline formats need a range; alignment and headings act on the block, so
    // they stay available with the caret merely resting somewhere.
    final selected = focus.hasSelection;

    return Focus(
      // Belt and braces over RoundedControl already being unfocusable: nothing
      // added here later can start stealing the editor's selection.
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _HeadingControl(
            level: focus.headingLevel,
            onPick: notifier.setHeadingLevel,
          ),
          const SizedBox(width: 6),
          for (final (format, icon) in const [
            (EditingFormat.bold, Icons.format_bold),
            (EditingFormat.italic, Icons.format_italic),
            (EditingFormat.strikethrough, Icons.format_strikethrough),
            (EditingFormat.underline, Icons.format_underlined),
          ]) ...[
            _ToolbarButton(
              icon: icon,
              active: focus.isActive(format),
              onPressed: selected ? () => notifier.toggleFormat(format) : null,
            ),
            const SizedBox(width: 6),
          ],
          for (final (align, icon) in const [
            (BlockAlign.left, Icons.format_align_left),
            (BlockAlign.center, Icons.format_align_center),
            (BlockAlign.right, Icons.format_align_right),
          ]) ...[
            _ToolbarButton(
              icon: icon,
              active: focus.align == align,
              onPressed: () => notifier.setAlign(align),
            ),
            if (align != BlockAlign.right) const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.active,
    required this.onPressed,
  });

  final IconData icon;
  final bool active;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return RoundedControl(
      onPressed: onPressed,
      active: active,
      child: Icon(
        icon,
        size: _kIconSize,
        color: onPressed == null ? colors.muted : colors.text,
      ),
    );
  }
}

/// One control rather than six buttons: the level is a choice, not a toggle.
class _HeadingControl extends StatelessWidget {
  const _HeadingControl({required this.level, required this.onPick});

  final int? level;
  final void Function(int?) onPick;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return RoundedControl(
      active: level != null,
      onPressed: () async {
        final box = context.findRenderObject() as RenderBox?;
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox?;
        if (box == null || overlay == null) return;

        // Body text is 0 rather than null, because showMenu also returns null
        // when the menu is dismissed — and turning a heading into body text
        // because someone pressed Escape would be its own small disaster.
        final picked = await showMenu<int>(
          context: context,
          position: RelativeRect.fromRect(
            Rect.fromPoints(
              box.localToGlobal(Offset.zero, ancestor: overlay),
              box.localToGlobal(
                box.size.bottomRight(Offset.zero),
                ancestor: overlay,
              ),
            ),
            Offset.zero & overlay.size,
          ),
          color: colors.island,
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.all(DsRadius.control),
            side: BorderSide(color: colors.border),
          ),
          items: [
            for (final (value, label) in const <(int, String)>[
              (0, 'Body text'),
              (1, 'Heading 1'),
              (2, 'Heading 2'),
              (3, 'Heading 3'),
              (4, 'Heading 4'),
            ])
              PopupMenuItem<int>(
                value: value,
                height: 32,
                child: Text(
                  label,
                  style: aleo(
                    size: 13,
                    weight: value == (level ?? 0) ? 600 : 400,
                    color: colors.text,
                  ),
                ),
              ),
          ],
        );

        if (picked == null) return; // dismissed
        onPick(picked == 0 ? null : picked);
      },
      // Sized to match the icon buttons exactly, so the row reads as one set
      // of controls rather than one wide one and six small ones.
      child: SizedBox(
        width: _kIconSize,
        height: _kIconSize,
        child: Center(
          child: level == null
              ? Icon(Icons.title, size: _kIconSize, color: colors.text)
              : FittedBox(
                  child: Text(
                    'H$level',
                    style: aleo(size: 11, weight: 600, color: colors.text),
                  ),
                ),
        ),
      ),
    );
  }
}
