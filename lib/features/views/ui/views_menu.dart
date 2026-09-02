/// The Views menu: what is placed on the screen.
///
/// Editor, Differences and Timelines share the shell's centre slot, so placing
/// one displaces the other and the menu marks whichever holds it. Below the
/// divider are the panes seated beside the centre, which toggle freely — which
/// panes those are depends on what is placed, so the shell supplies them
/// rather than this menu knowing.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

enum _ViewsWorkspace { editor, differences, timelines }

/// One pane the placed workspace has beside it, and how to toggle it.
@immutable
class ViewsPaneToggle {
  const ViewsPaneToggle({
    required this.id,
    required this.label,
    required this.visible,
    required this.onToggle,
  });

  /// Identifies the row as `Key(id)`, and its check mark as `Key('<id>-check')`.
  final String id;
  final String label;
  final bool visible;
  final VoidCallback onToggle;
}

class ViewsMenuButton extends ConsumerWidget {
  const ViewsMenuButton({
    super.key,
    required this.panes,
    this.pendingDifferencesCount = 0,
  });

  /// The panes beside whatever is currently placed, in the order they sit on
  /// screen.
  final List<ViewsPaneToggle> panes;

  final int pendingDifferencesCount;

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    final current = ref.read(viewProvider);
    // Object rather than a single enum: the panes below the divider are
    // supplied from outside and are not known here as values.
    final menu = DsDropdownMenuList<Object>();

    menu.pushItem(
      key: const Key('views-menu-editor'),
      value: _ViewsWorkspace.editor,
      label: 'Editor',
      isChecked: current == DsView.editor,
      leadingKey: const Key('views-menu-editor-check'),
    );
    menu.pushItem(
      key: const Key('views-menu-differences'),
      value: _ViewsWorkspace.differences,
      label: 'Differences',
      isChecked: current == DsView.differences,
      leadingKey: const Key('views-menu-differences-check'),
      trailing: pendingDifferencesCount > 0
          ? _PendingBadge(count: pendingDifferencesCount)
          : null,
    );
    menu.pushItem(
      key: const Key('views-menu-timelines'),
      value: _ViewsWorkspace.timelines,
      label: 'Timelines',
      isChecked: current == DsView.timelines,
      leadingKey: const Key('views-menu-timelines-check'),
    );

    if (panes.isNotEmpty) menu.pushDivider();
    for (final pane in panes) {
      menu.pushItem(
        key: Key(pane.id),
        value: pane,
        label: pane.label,
        isChecked: pane.visible,
        leadingKey: Key('${pane.id}-check'),
      );
    }

    final choice = await menu.show(context);
    if (choice == null) return;

    switch (choice) {
      // Selecting the workspace already in the centre slot changes nothing:
      // there is nowhere for it to go, and no empty centre to fall back to.
      case _ViewsWorkspace.editor:
        ref.read(viewProvider.notifier).state = DsView.editor;
      case _ViewsWorkspace.differences:
        ref.read(viewProvider.notifier).state = DsView.differences;
      case _ViewsWorkspace.timelines:
        ref.read(viewProvider.notifier).state = DsView.timelines;
      case final ViewsPaneToggle pane:
        pane.onToggle();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;

    return DsButton(
      key: const Key('views-menu-button'),
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      highlight: colors.selection,
      semanticLabel: 'Views',
      onPressed: () => _show(context, ref),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Views',
            style: uiTextStyle(size: 13, weight: 500, color: colors.text),
          ),
          if (pendingDifferencesCount > 0) ...[
            const SizedBox(width: DsSpace.xs),
            Container(
              key: const Key('views-menu-pending-dot'),
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                color: colors.pending,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The count of proposals waiting on this Knowledge Base.
class _PendingBadge extends StatelessWidget {
  const _PendingBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Container(
      key: const Key('views-differences-badge'),
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.pending,
        borderRadius: const BorderRadius.all(DsRadius.pill),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: uiTextStyle(size: 10, weight: 600, color: colors.text),
      ),
    );
  }
}
