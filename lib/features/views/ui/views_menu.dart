/// The Views menu: what is placed on the screen.
///
/// Editor, Differences and Timelines share the shell's centre slot, so placing
/// one displaces the other and the menu marks whichever holds it. The
/// Knowledge Base has a pane of its own beside them and toggles freely.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

enum _ViewsMenuItem { editor, differences, timelines, knowledgeBase }

class ViewsMenuButton extends ConsumerWidget {
  const ViewsMenuButton({
    super.key,
    required this.knowledgeBaseVisible,
    required this.onToggleKnowledgeBase,
    this.pendingDifferencesCount = 0,
  });

  final bool knowledgeBaseVisible;
  final VoidCallback onToggleKnowledgeBase;
  final int pendingDifferencesCount;

  Future<void> _show(BuildContext context, WidgetRef ref) async {
    final current = ref.read(viewProvider);
    final menu = DsDropdownMenuList<_ViewsMenuItem>();

    menu.pushItem(
      key: const Key('views-menu-editor'),
      value: _ViewsMenuItem.editor,
      label: 'Editor',
      isChecked: current == DsView.editor,
      leadingKey: const Key('views-menu-editor-check'),
    );
    menu.pushItem(
      key: const Key('views-menu-differences'),
      value: _ViewsMenuItem.differences,
      label: 'Differences',
      isChecked: current == DsView.differences,
      leadingKey: const Key('views-menu-differences-check'),
      trailing: pendingDifferencesCount > 0
          ? _PendingBadge(count: pendingDifferencesCount)
          : null,
    );
    menu.pushItem(
      key: const Key('views-menu-timelines'),
      value: _ViewsMenuItem.timelines,
      label: 'Timelines',
      isChecked: current == DsView.timelines,
      leadingKey: const Key('views-menu-timelines-check'),
    );
    menu.pushDivider();
    menu.pushItem(
      key: const Key('views-menu-knowledge-base'),
      value: _ViewsMenuItem.knowledgeBase,
      label: 'Knowledge Base',
      isChecked: knowledgeBaseVisible,
      leadingKey: const Key('views-menu-knowledge-base-check'),
    );

    final choice = await menu.show(context);
    if (choice == null) return;

    switch (choice) {
      // Selecting the workspace already in the centre slot changes nothing:
      // there is nowhere for it to go, and no empty centre to fall back to.
      case _ViewsMenuItem.editor:
        ref.read(viewProvider.notifier).state = DsView.editor;
      case _ViewsMenuItem.differences:
        ref.read(viewProvider.notifier).state = DsView.differences;
      case _ViewsMenuItem.timelines:
        ref.read(viewProvider.notifier).state = DsView.timelines;
      case _ViewsMenuItem.knowledgeBase:
        onToggleKnowledgeBase();
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
