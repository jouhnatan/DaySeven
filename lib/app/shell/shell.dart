/// The application frame: search across the top, feature menus on each side,
/// the selected view in the centre, and one bottom-bar control.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:dayseven/app/shell/pane_widths.dart';
import 'package:dayseven/features/auth/ui/auth_button.dart';
import 'package:dayseven/features/editing_toolbar/ui/editing_toolbar.dart';
import 'package:dayseven/features/gradient_background/ui/gradient_background.dart';
import 'package:dayseven/features/hamburger_menu/ui/hamburger_menu_button.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/review/data/proposals.dart';
import 'package:dayseven/features/review/ui/review_inbox.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/home/ui/home_screen.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_menu.dart';
import 'package:dayseven/features/search/ui/search_bar.dart';
import 'package:dayseven/features/views/ui/views_menu.dart';

class DsShell extends ConsumerWidget {
  const DsShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);
    final colors = context.ds;
    final brightness = Theme.of(context).brightness;

    return ValueListenableBuilder<DsAppSettings>(
      valueListenable: DsGlobalSettings.listenable,
      builder: (context, settings, _) {
        final showGradient =
            view == DsView.home || settings.gradientBackgroundEnabled;

        return Scaffold(
          backgroundColor: showGradient
              ? gradientShellBackground(brightness)
              : colors.appBackground,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (showGradient)
                GradientBackground(isDark: brightness == Brightness.dark),
              Column(
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
                          final visibility = ref.watch(paneVisibilityProvider);
                          final paneVisibility = ref.read(
                            paneVisibilityProvider.notifier,
                          );
                          final fullyOpenAvailable =
                              constraints.maxWidth - DsSpace.islandGap * 2;

                          return TweenAnimationBuilder<double>(
                            tween: Tween<double>(
                              begin: 1,
                              end: visibility.knowledgeBase ? 1 : 0,
                            ),
                            duration: DsMotion.pane,
                            curve: Curves.easeInOutCubic,
                            builder: (context, panelProgress, _) {
                              final available =
                                  constraints.maxWidth -
                                  DsSpace.islandGap * (1 + panelProgress);

                              return Column(
                                children: [
                                  SizedBox(
                                    height: kSearchHeight,
                                    child: Align(
                                      alignment: Alignment.centerRight,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Collaboration needs a server; without
                                          // one there is nothing to sign in to.
                                          if (isSupabaseConfigured) ...[
                                            const Flexible(child: AuthButton()),
                                            const SizedBox(
                                              width: DsSpace.controlGap,
                                            ),
                                          ],
                                          HamburgerMenuButton(
                                            entries: [
                                              HamburgerMenuEntry.toggle(
                                                label: 'Knowledge Base',
                                                checked:
                                                    visibility.knowledgeBase,
                                                onSelected: paneVisibility
                                                    .toggleKnowledgeBase,
                                              ),
                                              HamburgerMenuEntry.toggle(
                                                label:
                                                    'Gradient on Other Views',
                                                checked: settings
                                                    .gradientBackgroundEnabled,
                                                onSelected: DsGlobalSettings
                                                    .toggleGradientBackground,
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: DsSpace.islandGap),
                                  Expanded(
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        SizedBox(
                                          width: widths.rail,
                                          child: const ViewsMenu(),
                                        ),
                                        _ResizeHandle(
                                          onDrag: (dx) => panes.dragRail(
                                            dx,
                                            available,
                                            reservedPanelWidth:
                                                widths.panel * panelProgress,
                                          ),
                                        ),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              // Side-menu surfaces sit below a heading.
                                              // Reserve the same header row here so
                                              // every workspace starts at one height.
                                              const DsMenuHeader.spacer(),
                                              const SizedBox(
                                                height: DsSpace.islandGap,
                                              ),
                                              Expanded(
                                                child: switch (view) {
                                                  // The shell supplies Home's
                                                  // optional full-window backdrop.
                                                  DsView.home =>
                                                    const HomeScreen(),
                                                  DsView.editor =>
                                                    const DsIsland(
                                                      editorSurface: true,
                                                      child: EditorScreen(
                                                        searchCard: DsSearchBar(
                                                          resultsAbove: true,
                                                        ),
                                                      ),
                                                    ),
                                                },
                                              ),
                                            ],
                                          ),
                                        ),
                                        _SlidingKnowledgeBasePane(
                                          progress: panelProgress,
                                          panelWidth: widths.panel,
                                          visible: visibility.knowledgeBase,
                                          onDrag: (dx) => panes.dragPanel(
                                            dx,
                                            fullyOpenAvailable,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),
                  const _BottomBar(),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A fixed-width right pane revealed through an animated slot. As the slot
/// narrows, its child stays anchored to the slot's left and travels out past
/// the window's right edge instead of being squeezed.
class _SlidingKnowledgeBasePane extends StatelessWidget {
  const _SlidingKnowledgeBasePane({
    required this.progress,
    required this.panelWidth,
    required this.visible,
    required this.onDrag,
  });

  final double progress;
  final double panelWidth;
  final bool visible;
  final void Function(double delta) onDrag;

  @override
  Widget build(BuildContext context) {
    final fullWidth = panelWidth + DsSpace.islandGap;

    return SizedBox(
      key: const Key('knowledge-base-slide-region'),
      width: fullWidth * progress,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: fullWidth,
          maxWidth: fullWidth,
          child: ExcludeSemantics(
            excluding: !visible,
            child: IgnorePointer(
              ignoring: !visible,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ResizeHandle(onDrag: onDrag),
                  SizedBox(
                    key: const Key('knowledge-base-pane'),
                    width: panelWidth,
                    child: const KnowledgeBaseMenu(),
                  ),
                ],
              ),
            ),
          ),
        ),
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

const double _kToolbarIslandVerticalPadding = 6;

/// The formatting toolbar and its overflow menu while the Editor is active.
/// Other views keep the same taller footprint so the three main islands do not
/// change height when the workspace changes.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);
    final showingEditor = view == DsView.editor;

    // With nothing being edited there is no toolbar, and the bar has to look
    // exactly as it did before there was one — gap included.
    final editing = showingEditor && ref.watch(editingFocusProvider) != null;

    if (editing) {
      final widths = ref.watch(paneWidthsProvider);
      final visibility = ref.watch(paneVisibilityProvider);

      return Padding(
        padding: const EdgeInsets.fromLTRB(
          DsSpace.pane,
          DsSpace.islandGap,
          DsSpace.pane,
          DsSpace.pane,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => TweenAnimationBuilder<double>(
            tween: Tween<double>(
              begin: 1,
              end: visibility.knowledgeBase ? 1 : 0,
            ),
            duration: DsMotion.pane,
            curve: Curves.easeInOutCubic,
            builder: (context, panelProgress, _) => Row(
              children: [
                SizedBox(width: widths.rail + DsSpace.islandGap),
                const Expanded(child: _EditingToolbarIsland()),
                SizedBox(
                  width: (widths.panel + DsSpace.islandGap) * panelProgress,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      // The islands sit one island-gap above the bar, the same distance that
      // separates them from each other; below it is the window margin.
      padding: const EdgeInsets.fromLTRB(0, DsSpace.islandGap, 0, DsSpace.pane),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showingEditor)
            const Padding(
              key: Key('editor-toolbar-menu-footprint'),
              padding: EdgeInsets.symmetric(
                vertical: _kToolbarIslandVerticalPadding,
              ),
              child: EditorToolbarMenuButton(),
            )
          else
            const _BottomBarFootprint(),
        ],
      ),
    );
  }
}

/// The editor-width surface that carries the formatting and review buttons.
///
/// Its parent mirrors the shell's resizable side-pane slots, so this island's
/// horizontal bounds always follow the editor above it.
class _EditingToolbarIsland extends StatelessWidget {
  const _EditingToolbarIsland();

  @override
  Widget build(BuildContext context) {
    return DsIsland(
      key: const Key('editing-toolbar-island'),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: _kToolbarIslandVerticalPadding,
        ),
        child: Row(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: const Center(child: EditingToolbar()),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DsSpace.islandGap),
            const EditorToolbarMenuButton(),
          ],
        ),
      ),
    );
  }
}

/// An invisible control-sized spacer. Its padding matches the toolbar island,
/// keeping the Views, workspace, and Knowledge Base islands equally short.
class _BottomBarFootprint extends StatelessWidget {
  const _BottomBarFootprint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('bottom-bar-footprint'),
      padding: const EdgeInsets.symmetric(
        vertical: _kToolbarIslandVerticalPadding,
      ),
      child: IgnorePointer(
        child: Opacity(
          opacity: 0,
          child: DsButton(
            height: 34,
            padding: EdgeInsets.zero,
            child: Icon(Icons.more_horiz, size: 18, color: context.ds.muted),
          ),
        ),
      ),
    );
  }
}

enum _EditorToolbarMenuAction { syncLatest, differences }

/// Overflow actions for the active document.
///
/// Differences stays present as a list-menu action and becomes available when
/// another account has a proposal waiting on the open document.
class EditorToolbarMenuButton extends ConsumerWidget {
  const EditorToolbarMenuButton({super.key});

  Future<void> _show(
    BuildContext context, {
    required VoidCallback? openDifferences,
    required Future<void> Function()? syncLatest,
    required bool hasPendingProposal,
  }) async {
    final colors = context.ds;
    final choice = await showDsMenu<_EditorToolbarMenuAction>(
      context: context,
      items: [
        DsMenuItem<_EditorToolbarMenuAction>(
          value: _EditorToolbarMenuAction.syncLatest,
          enabled: syncLatest != null,
          child: Text(
            'Sync latest',
            style: uiTextStyle(
              size: 13,
              color: syncLatest == null ? colors.muted : colors.text,
            ),
          ),
        ),
        const DsMenuDivider(),
        DsMenuItem<_EditorToolbarMenuAction>(
          key: const Key('editor-menu-differences'),
          value: _EditorToolbarMenuAction.differences,
          enabled: openDifferences != null,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Differences',
                  style: uiTextStyle(
                    size: 13,
                    color: openDifferences == null ? colors.muted : colors.text,
                  ),
                ),
              ),
              if (hasPendingProposal) ...[
                const SizedBox(width: 12),
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
        ),
      ],
    );

    if (!context.mounted) return;
    if (choice == _EditorToolbarMenuAction.differences) {
      openDifferences?.call();
    } else if (choice == _EditorToolbarMenuAction.syncLatest) {
      await syncLatest?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final proposals = ref.watch(pendingProposalsProvider);
    final role = ref.watch(kbRoleProvider).valueOrNull;
    final mayReview =
        role == KbRole.owner ||
        role == KbRole.coOwner ||
        role == KbRole.reviewer;
    final VoidCallback? openDifferences = mayReview && proposals.isNotEmpty
        ? () => Navigator.of(context).push(reviewInboxRoute())
        : null;
    final canSync =
        role != null && role != KbRole.local && role != KbRole.invited;

    Future<void> syncLatest() async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        final result = await ref
            .read(sharingControllerProvider)
            .pullRemoteChanges();
        final parts = <String>[
          '${result.updated} updated',
          '${result.recoveredDeletions} recovered deletion(s)',
        ];
        if (result.conflicts > 0) {
          parts.add('${result.conflicts} local conflict(s) left untouched');
        }
        messenger?.showSnackBar(SnackBar(content: Text(parts.join(' · '))));
      } catch (error) {
        messenger?.showSnackBar(SnackBar(content: Text('$error')));
      }
    }

    return Tooltip(
      message: 'Editor menu',
      child: SizedBox.square(
        key: const Key('editor-toolbar-menu-button'),
        dimension: 34,
        child: DsButton(
          height: 34,
          padding: EdgeInsets.zero,
          onPressed: () => _show(
            context,
            openDifferences: openDifferences,
            syncLatest: canSync ? syncLatest : null,
            hasPendingProposal: proposals.isNotEmpty,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.more_horiz, size: 18, color: colors.text),
              if (proposals.isNotEmpty)
                Positioned(
                  top: 5,
                  right: 5,
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.pending,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
