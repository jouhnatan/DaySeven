/// The application frame: search bar across the top, service rail on the left,
/// Knowledge Base island on the right, and one bottom-bar control.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/state.dart';
import 'package:dayseven/auth/auth_button.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/sync/proposals.dart';
import 'package:dayseven/ui/diff/diff_screen.dart';
import 'package:dayseven/ui/editor/editor_screen.dart';
import 'package:dayseven/ui/home/home_screen.dart';
import 'package:dayseven/ui/shell/kb_island.dart';
import 'package:dayseven/search/search_bar.dart';
import 'package:dayseven/ui/shell/service_rail.dart';

class DsShell extends ConsumerWidget {
  const DsShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider);
    final colors = context.ds;

    return Scaffold(
      backgroundColor: colors.appBackground,
      body: Column(
        children: [
          Expanded(
            child: Padding(
              // The bottom bar supplies the gap beneath the islands, so that
              // it matches the gap between them.
              padding: const EdgeInsets.fromLTRB(
                DsSpace.pane,
                DsSpace.pane,
                DsSpace.pane,
                0,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final widths = ref.watch(paneWidthsProvider);
                  final panes = ref.read(paneWidthsProvider.notifier);
                  // What the three panes share, once the two handles are taken
                  // out; the controller keeps the editor above its minimum.
                  final available =
                      constraints.maxWidth - DsSpace.islandGap * 2;

                  // The search bar is centred over the workspace rather than
                  // the window, so it stays with the editor as the panes are
                  // resized.
                  return Column(
                    children: [
                      Row(
                        children: [
                          SizedBox(width: widths.rail + DsSpace.islandGap),
                          const Expanded(child: Center(child: DsSearchBar())),
                          SizedBox(
                            width: widths.panel + DsSpace.islandGap,
                            // Collaboration needs a server; without one there
                            // is nothing to sign in to.
                            child: isSupabaseConfigured
                                ? const Align(
                                    alignment: Alignment.centerRight,
                                    child: AuthButton(),
                                  )
                                : null,
                          ),
                        ],
                      ),
                      const SizedBox(height: DsSpace.islandGap),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              width: widths.rail,
                              child: const ServiceRail(),
                            ),
                            _ResizeHandle(
                              onDrag: (dx) => panes.dragRail(dx, available),
                            ),
                            Expanded(
                              child: DsIsland(
                                editorSurface: true,
                                child: switch (service) {
                                  DsService.home => const HomeScreen(),
                                  DsService.editor => const EditorScreen(),
                                },
                              ),
                            ),
                            _ResizeHandle(
                              onDrag: (dx) => panes.dragPanel(dx, available),
                            ),
                            SizedBox(
                              width: widths.panel,
                              child: const KbIsland(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const _BottomBar(),
        ],
      ),
    );
  }
}

/// The gap between two islands, which is also where they are resized from.
///
/// It draws nothing: the application background showing between the panes is
/// the separator, and the cursor is what says the gap can be dragged.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});

  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeLeftRight,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        child: const SizedBox(width: DsSpace.islandGap),
      ),
    );
  }
}

/// A rounded pane sitting on the application background. The editor uses the
/// editor surface tone; the rails either side use the island tone, a step
/// apart, so the three read as separate pieces of one window.
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
        border: Border.all(color: colors.border, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

/// Holds exactly one control — Differences — and only while the Editor service
/// is showing.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = ref.watch(serviceProvider);

    // With no bar to show, the islands simply run down to the window margin.
    if (service != DsService.editor) {
      return const SizedBox(height: DsSpace.pane);
    }

    return const Padding(
      // The islands sit one island-gap above the bar, the same distance that
      // separates them from each other; below it is the window margin.
      padding: EdgeInsets.fromLTRB(0, DsSpace.islandGap, 0, DsSpace.pane),
      child: Center(child: DifferencesButton()),
    );
  }
}

/// Opens the split diff for the document being edited. Carries a subdued dot
/// when a proposal is waiting; no badge, no count.
class DifferencesButton extends ConsumerWidget {
  const DifferencesButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(documentControllerProvider);
    final pending = ref.watch(pendingProposalProvider);
    final enabled = open != null && pending != null;

    return _RoundedControl(
      onPressed: enabled
          ? () => Navigator.of(context).push(diffRoute(pending))
          : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Differences',
            style: aleo(
              size: 13,
              weight: 500,
              color: enabled ? colors.text : colors.muted,
            ),
          ),
          if (pending != null) ...[
            const SizedBox(width: 8),
            Container(
              width: 6,
              height: 6,
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

class _RoundedControl extends StatefulWidget {
  const _RoundedControl({required this.child, this.onPressed});

  final Widget child;
  final VoidCallback? onPressed;

  @override
  State<_RoundedControl> createState() => _RoundedControlState();
}

class _RoundedControlState extends State<_RoundedControl> {
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
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered && enabled ? colors.selection : colors.island,
            borderRadius: const BorderRadius.all(DsRadius.control),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: widget.child,
        ),
      ),
    );
  }
}
