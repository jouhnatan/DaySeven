/// The screen the application opens to: a welcome, and the documents the user
/// was last working on. Search lives in the persistent bar at the top.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/app/state.dart';
import 'package:dayseven/shared/ui/theme.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final session = ref.watch(kbSessionProvider);
    final recents = ref.watch(recentDocumentsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(40, 44, 40, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back!',
            style: aleo(size: 30, weight: 600, color: colors.text),
          ),
          const SizedBox(height: 32),
          Text(
            'Recent files',
            style: aleo(size: 12, weight: 600, color: colors.muted),
          ),
          const SizedBox(height: 8),
          if (session == null)
            Text(
              'Open a Knowledge Base to begin.',
              style: aleo(size: 13, color: colors.muted),
            )
          else
            recents.when(
              loading: () => const SizedBox.shrink(),
              error: (error, _) =>
                  Text('$error', style: aleo(size: 13, color: colors.muted)),
              data: (paths) => paths.isEmpty
                  ? Text(
                      'Nothing opened yet.',
                      style: aleo(size: 13, color: colors.muted),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final path in paths)
                          _RecentRow(
                            relativePath: path,
                            onTap: () async {
                              await ref
                                  .read(documentControllerProvider.notifier)
                                  .open(path);
                              ref.read(serviceProvider.notifier).state =
                                  DsService.editor;
                            },
                          ),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}

class _RecentRow extends StatefulWidget {
  const _RecentRow({required this.relativePath, required this.onTap});

  final String relativePath;
  final VoidCallback onTap;

  @override
  State<_RecentRow> createState() => _RecentRowState();
}

class _RecentRowState extends State<_RecentRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final folder = p.posix.dirname(widget.relativePath);

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
            color: _hovered ? colors.selection : Colors.transparent,
            borderRadius: const BorderRadius.all(DsRadius.row),
          ),
          child: Row(
            children: [
              Text(
                p.posix.basenameWithoutExtension(widget.relativePath),
                style: aleo(size: 14, color: colors.text),
              ),
              if (folder != '.') ...[
                const SizedBox(width: 10),
                Text(folder, style: aleo(size: 12, color: colors.muted)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
