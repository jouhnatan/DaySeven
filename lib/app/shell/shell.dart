/// The application frame: search across the top, feature menus on each side,
/// the selected view in the centre, and one bottom-bar control.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/document_publish_controls.dart';
import 'package:dayseven/app/workspace/document_presence_indicator.dart';
import 'package:dayseven/app/workspace/presence.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:dayseven/app/shell/pane_widths.dart';
import 'package:dayseven/features/app_settings/ui/app_settings_dialog.dart';
import 'package:dayseven/features/auth/ui/auth_button.dart';
import 'package:dayseven/features/editing_toolbar/ui/editing_toolbar.dart';
import 'package:dayseven/features/hamburger_menu/ui/hamburger_menu_button.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/application/differences_navigation.dart';
import 'package:dayseven/features/differences/ui/differences_workspace.dart';
import 'package:dayseven/features/differences/ui/sync_status_indicator.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/home/ui/home_screen.dart';
import 'package:dayseven/features/notifications/ui/notifications_panel.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_menu.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_settings.dart';
import 'package:dayseven/features/search/ui/search_bar.dart';
import 'package:dayseven/app/workspace/crdt_collaboration.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:dayseven/features/timeline/ui/timeline_toolbar_button.dart';
import 'package:dayseven/features/timeline/ui/timeline_widget.dart';
import 'package:dayseven/features/views/ui/views_menu.dart';
import 'package:dayseven/shared/platform/new_instance.dart';
import 'package:dayseven/shared/ui/error_box.dart';

class DsShell extends ConsumerWidget {
  const DsShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(incomingCanonicalSyncProvider);
    // Held here rather than left to whichever widget happens to read a peer
    // first, so the channel's lifetime is the shell's and not a panel's.
    ref.watch(presenceControllerProvider.select((_) => null));
    // Same reasoning: the CRDT session belongs to the open Knowledge Base, not
    // to whichever screen first asks about collaboration.
    ref.watch(crdtCollaborationProvider.select((_) => null));
    final view = ref.watch(viewProvider);
    final pendingDifferencesCount = ref.watch(
      differencesStateProvider.select((state) => state.pendingCount),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          unawaited(publishOpenDocumentFromShortcut(context, ref));
        },
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          unawaited(publishOpenDocumentFromShortcut(context, ref));
        },
      },
      child: Scaffold(
        backgroundColor: context.ds.appBackground,
        body: Column(
          children: [
            Expanded(
              // Seated: the panes run to the window edge, and the seams
              // between them are the only thing separating one from the next.
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final widths = ref.watch(paneWidthsProvider);
                  final panes = ref.read(paneWidthsProvider.notifier);
                  final visibility = ref.watch(paneVisibilityProvider);
                  final paneVisibility = ref.read(
                    paneVisibilityProvider.notifier,
                  );
                  final fullyOpenAvailable =
                      constraints.maxWidth - DsSpace.seam * 2;

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
                          DsSpace.seam * (1 + panelProgress);

                      return Column(
                        children: [
                          _TitleBar(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Collaboration needs a server; without
                                  // one there is nothing to sign in to.
                                  if (isSupabaseConfigured) ...[
                                    const AuthButton(),
                                    const SizedBox(width: DsSpace.controlGap),
                                  ],
                                  HamburgerMenuButton(
                                    entries: [
                                      HamburgerMenuEntry.toggle(
                                        label: 'Knowledge Base',
                                        checked: visibility.knowledgeBase,
                                        onSelected:
                                            paneVisibility.toggleKnowledgeBase,
                                      ),
                                      if (canOpenNewWindow) ...[
                                        HamburgerMenuEntry.action(
                                          label: 'New Window',
                                          onSelected: () => _openNewWindow(
                                            context,
                                            fresh: false,
                                          ),
                                        ),
                                        HamburgerMenuEntry.action(
                                          label:
                                              'New Window as '
                                              'Different Account…',
                                          onSelected: () => _openNewWindow(
                                            context,
                                            fresh: true,
                                          ),
                                        ),
                                      ],
                                      // Shown with or without a
                                      // server: the version is worth
                                      // seeing either way, and the
                                      // dialog says so itself when
                                      // there is nothing to check
                                      // against.
                                      HamburgerMenuEntry.action(
                                        label: 'Settings',
                                        onSelected: () =>
                                            _openAppSettings(context),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                SizedBox(
                                  width: widths.rail,
                                  child: DsPane(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                          child: ViewsMenu(
                                            pendingDifferencesCount:
                                                pendingDifferencesCount,
                                          ),
                                        ),
                                        const DsSeam.horizontal(),
                                        const DsMenuHeader('Notifications'),
                                        const Expanded(
                                          child: NotificationsPanel(),
                                        ),
                                      ],
                                    ),
                                  ),
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
                                      Expanded(
                                        child: switch (view) {
                                          DsView.home => const HomeScreen(),
                                          DsView.editor => const DsPane(
                                            editorSurface: true,
                                            child: EditorScreen(
                                              timelineWidget: TimelineWidget(),
                                              searchCard: DsSearchBar(
                                                resultsAbove: true,
                                              ),
                                            ),
                                          ),
                                          DsView.differences =>
                                            const DifferencesWorkspace(),
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                _SlidingKnowledgeBasePane(
                                  progress: panelProgress,
                                  panelWidth: widths.panel,
                                  visible: visibility.knowledgeBase,
                                  onDrag: (dx) =>
                                      panes.dragPanel(dx, fullyOpenAvailable),
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
            const _BottomBar(),
          ],
        ),
      ),
    );
  }
}

/// Opens another copy of DaySeven.
///
/// A failure here is worth saying out loud: the person asked for a window and
/// did not get one, and nothing else on screen would show why.
void _openNewWindow(BuildContext context, {required bool fresh}) {
  unawaited(() async {
    try {
      await openNewWindow(fresh: fresh);
    } on NewInstanceException catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: DsErrorBox(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }());
}

/// Opens App settings with everything only the composition root can supply:
/// the developer options, and the Knowledge Base panel, which belongs to a
/// feature App settings is not allowed to import.
void _openAppSettings(
  BuildContext context, {
  AppSettingsSection section = AppSettingsSection.updates,
}) {
  unawaited(
    showAppSettingsDialog(
      context,
      developerOptions: _developerOptions,
      knowledgeBasePanelBuilder: _knowledgeBaseSettingsPanel,
      initialSection: section,
    ),
  );
}

Widget _knowledgeBaseSettingsPanel(WidgetRef ref) {
  final collaboration = ref.watch(crdtCollaborationProvider);
  final link = collaboration.linkState;
  final state = collaboration.unavailable != null
      ? KbConnectionState.error
      : switch (link.connection) {
          CrdtConnectionState.disconnected => KbConnectionState.disconnected,
          CrdtConnectionState.connecting => KbConnectionState.connecting,
          CrdtConnectionState.connected => KbConnectionState.connected,
          CrdtConnectionState.error => KbConnectionState.error,
        };

  return KnowledgeBaseSettingsPanel(
    collaborationStatus: KbCollaborationStatus(
      state: state,
      waitingForPeer: link.waitingForPeer,
      detail: collaboration.unavailable ?? link.detail,
      refusalCount: collaboration.refusalCount,
      refusalDetail: collaboration.lastRefusal?.detail,
    ),
  );
}

AppSettingsDeveloperOptions _developerOptions(WidgetRef ref) {
  final settings =
      ref.watch(developerSettingsProvider).valueOrNull ??
      const DeveloperSettings();
  return AppSettingsDeveloperOptions(
    showWorkspaceMetadata: settings.showWorkspaceMetadata,
    setShowWorkspaceMetadata: (enabled) async {
      await ref
          .read(developerSettingsProvider.notifier)
          .setShowWorkspaceMetadata(enabled);
      await ref
          .read(kbControllerProvider.notifier)
          .setWorkspaceMetadataVisible(enabled);
    },
  );
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
    final fullWidth = panelWidth + DsSpace.seam;

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
                    child: KnowledgeBaseMenu(
                      // The gear beside the Knowledge Base selector opens the
                      // same App settings everything else does, on the section
                      // that describes the Knowledge Base it sits next to.
                      onOpenSettings: () => _openAppSettings(
                        context,
                        section: AppSettingsSection.knowledgeBase,
                      ),
                    ),
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

/// The seam between two panes, which is also where they are resized from.
///
/// It takes one pixel of layout and draws the line itself. The grab target
/// reaches past the line into both neighbours, so a 1px seam is still
/// comfortable to catch with a mouse without costing the panes any width.
class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle({required this.onDrag});

  final void Function(double delta) onDrag;

  /// How far the drag target reaches either side of the line.
  static const double _grabOverhang = 5;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: DsSpace.seam,
      child: _HorizontalHitSlop(
        slop: _grabOverhang,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
            child: const DsSeam.vertical(),
          ),
        ),
      ),
    );
  }
}

/// Accepts pointers that land within [slop] pixels to either side of the
/// child, without changing how much room the child takes or how it paints.
class _HorizontalHitSlop extends SingleChildRenderObjectWidget {
  const _HorizontalHitSlop({required this.slop, required super.child});

  final double slop;

  @override
  _RenderHorizontalHitSlop createRenderObject(BuildContext context) =>
      _RenderHorizontalHitSlop(slop);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderHorizontalHitSlop renderObject,
  ) {
    renderObject.slop = slop;
  }
}

class _RenderHorizontalHitSlop extends RenderProxyBox {
  _RenderHorizontalHitSlop(this._slop);

  double _slop;

  set slop(double value) {
    if (value == _slop) return;
    _slop = value;
    markNeedsLayout();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final widened =
        Rect.fromLTWH(-_slop, 0, size.width + _slop * 2, size.height);
    if (!widened.contains(position)) return false;
    // Clamp onto the child, so its own hit test sees a pointer inside it.
    final clamped = Offset(
      position.dx.clamp(0.0, size.width).toDouble(),
      position.dy,
    );
    return super.hitTest(result, position: clamped);
  }
}

/// The strip across the top of the window: the account control and the
/// application menu, on the toolbar surface, closed by a seam.
class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: kSearchHeight,
          padding: const EdgeInsets.symmetric(horizontal: DsSpace.sm),
          color: context.ds.bar,
          child: child,
        ),
        const DsSeam.horizontal(),
      ],
    );
  }
}

const double _kToolbarIslandVerticalPadding = 6;

/// The formatting toolbar and its overflow menu while the Editor is active.
/// Other views keep the same taller footprint so the panes above do not change
/// height when the workspace changes.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);
    final showingEditor = view == DsView.editor;

    // With nothing being edited there is no toolbar, and the bar has to look
    // exactly as it did before there was one.
    final editing = showingEditor && ref.watch(editingFocusProvider) != null;

    if (editing) {
      final widths = ref.watch(paneWidthsProvider);
      final visibility = ref.watch(paneVisibilityProvider);

      return _Footer(
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
                SizedBox(width: widths.rail + DsSpace.seam),
                const Expanded(child: _EditingToolbarIsland()),
                SizedBox(width: (widths.panel + DsSpace.seam) * panelProgress),
              ],
            ),
          ),
        ),
      );
    }

    return _Footer(
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

/// The full-width strip across the bottom of the window, closed by a seam
/// where it meets the panes above it.
class _Footer extends StatelessWidget {
  const _Footer({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const DsSeam.horizontal(),
        ColoredBox(color: context.ds.island, child: child),
      ],
    );
  }
}

/// The editor-width surface that carries the formatting and review buttons.
///
/// Its parent mirrors the shell's resizable side-pane slots, so this surface's
/// horizontal bounds always follow the editor above it.
class _EditingToolbarIsland extends StatelessWidget {
  const _EditingToolbarIsland();

  @override
  Widget build(BuildContext context) {
    return DsPane(
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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        EditingToolbar(),
                        SizedBox(width: DsSpace.controlGap),
                        TimelineToolbarButton(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DsSpace.gap),
            const DocumentPresenceIndicator(),
            const DocumentReviewSyncIndicator(),
            const SizedBox(width: DsSpace.controlGap),
            const DocumentPublishButton(),
            const SizedBox(width: DsSpace.controlGap),
            const DocumentProtectionButton(),
            const SizedBox(width: DsSpace.controlGap),
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

enum _EditorToolbarMenuAction { differences }

/// Overflow actions for the active document.
///
/// Differences stays present as a list-menu action and becomes available when
/// another account has a proposal waiting on the open document.
class EditorToolbarMenuButton extends ConsumerWidget {
  const EditorToolbarMenuButton({super.key});

  Future<void> _show(
    BuildContext context, {
    required VoidCallback? openDifferences,
    required bool hasPendingProposal,
  }) async {
    final colors = context.ds;
    final menu = DsDropdownMenuList<_EditorToolbarMenuAction>();
    menu.pushItem(
      key: const Key('editor-menu-differences'),
      value: _EditorToolbarMenuAction.differences,
      label: 'Differences',
      tooltip: openDifferences == null
          ? 'No pending edits for this document.'
          : 'Review pending edits for this document.',
      enabled: openDifferences != null,
      trailing: hasPendingProposal
          ? Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: colors.pending,
                shape: BoxShape.circle,
              ),
            )
          : null,
    );

    final choice = await menu.show(context);

    if (!context.mounted) return;
    if (choice == _EditorToolbarMenuAction.differences) {
      openDifferences?.call();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final documentProposals = ref.watch(differencesForOpenDocumentProvider);
    final open = ref.watch(documentControllerProvider);
    final role = ref.watch(kbRoleProvider).valueOrNull;
    final mayReview =
        role == KbRole.owner ||
        role == KbRole.coOwner ||
        role == KbRole.reviewer;
    final VoidCallback? openDifferences =
        mayReview && open != null && documentProposals.isNotEmpty
        ? () => openDifferencesForDocument(context, ref, open.document.id)
        : null;
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
            hasPendingProposal: documentProposals.isNotEmpty,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(Icons.more_horiz, size: 18, color: colors.text),
              if (documentProposals.isNotEmpty)
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
