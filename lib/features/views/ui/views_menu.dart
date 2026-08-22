/// The left-side Views menu: Home and Editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class ViewsMenu extends ConsumerWidget {
  const ViewsMenu({super.key, this.pendingDifferencesCount = 0});

  final int pendingDifferencesCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(viewProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DsMenuHeader('Views'),
        const SizedBox(height: DsSpace.islandGap),
        Expanded(
          child: DsIsland(
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final view in DsView.values)
                    _ViewRow(
                      label: switch (view) {
                        DsView.home => 'Home',
                        DsView.editor => 'Editor',
                        DsView.differences => 'Differences',
                      },
                      badgeCount: view == DsView.differences
                          ? pendingDifferencesCount
                          : 0,
                      selected: view == current,
                      onTap: () => ref.read(viewProvider.notifier).state = view,
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ViewRow extends StatelessWidget {
  const _ViewRow({
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsHoverRow(
      onTap: onTap,
      selected: selected,
      margin: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: uiTextStyle(
                size: 13,
                weight: selected ? 600 : 400,
                color: selected ? colors.text : colors.muted,
              ),
            ),
          ),
          if (badgeCount > 0)
            Container(
              key: const Key('views-differences-badge'),
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colors.pending,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                '$badgeCount',
                textAlign: TextAlign.center,
                style: uiTextStyle(size: 10, weight: 600, color: colors.text),
              ),
            ),
        ],
      ),
    );
  }
}
