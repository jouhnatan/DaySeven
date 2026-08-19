/// The left-hand rail. Services, not tools: Home and Editor.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/service.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/ui/shell/shell.dart';

class ServiceRail extends ConsumerWidget {
  const ServiceRail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(serviceProvider);

    return DsIsland(
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final service in DsService.values)
              _ServiceRow(
                label: switch (service) {
                  DsService.home => 'Home',
                  DsService.editor => 'Editor',
                },
                selected: service == current,
                onTap: () => ref.read(serviceProvider.notifier).state = service,
              ),
          ],
        ),
      ),
    );
  }
}

class _ServiceRow extends StatefulWidget {
  const _ServiceRow({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ServiceRow> createState() => _ServiceRowState();
}

class _ServiceRowState extends State<_ServiceRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: widget.selected
                ? colors.selection
                : _hovered
                ? colors.selection.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: const BorderRadius.all(DsRadius.row),
          ),
          child: Text(
            widget.label,
            style: aleo(
              size: 13,
              weight: widget.selected ? 600 : 400,
              color: widget.selected ? colors.text : colors.muted,
            ),
          ),
        ),
      ),
    );
  }
}
