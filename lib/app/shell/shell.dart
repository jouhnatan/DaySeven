/// The application frame: one bar across the top carrying the menus, Search
/// and the account control, the placed workspace in the centre, the Knowledge
/// Base beside it, and one bottom-bar control.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/editing_focus.dart';
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
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/application/differences_navigation.dart';
import 'package:dayseven/features/differences/ui/differences_workspace.dart';
import 'package:dayseven/features/differences/ui/sync_status_indicator.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/features/notifications/ui/notifications_bell_button.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_menu.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_settings.dart';
import 'package:dayseven/features/search/ui/search_bar.dart';
import 'package:dayseven/app/workspace/crdt_collaboration.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:dayseven/features/timelines/ui/timeline_editor_pane.dart';
import 'package:dayseven/features/timelines/map_renderer/timeline_map_canvas.dart';
import 'package:dayseven/features/timelines/ui/timeline_reader_pane.dart';
import 'package:dayseven/features/timelines/ui/timeline_strip.dart';
import 'package:dayseven/features/views/ui/views_menu.dart';
import 'package:dayseven/features/world/world_renderer/world_canvas.dart';
import 'package:dayseven/features/world/ui/world_settings_pane.dart';
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
                  // A slot each side of the centre, holding whichever panes
                  // the placed workspace belongs with, each at its own width
                  // and its own visibility. World fills the left slot too, and
                  // is the only view with no right-hand pane.
                  final showingTimelines = view == DsView.timelines;
                  final showingWorld = view == DsView.world;
                  final rightVisible = switch (view) {
                    DsView.timelines => visibility.timelineReader,
                    DsView.world => false,
                    DsView.editor ||
                    DsView.differences => visibility.knowledgeBase,
                  };
                  final rightWidth = showingTimelines
                      ? widths.reader
                      : widths.panel;
                  final leftVisible = switch (view) {
                    DsView.timelines => visibility.timelineEditor,
                    DsView.world => visibility.world,
                    DsView.editor || DsView.differences => false,
                  };
                  final leftWidth = showingWorld ? widths.world : widths.editor;
                  final rightProgress = rightVisible ? 1.0 : 0.0;
                  final leftProgress = leftVisible ? 1.0 : 0.0;
                  final available =
                      constraints.maxWidth -
                      DsSpace.seam * (rightProgress + leftProgress);

                  return Column(
                    children: [
                      _TitleBar(
                        leading: [
                          ViewsMenuButton(
                            // Which panes exist depends on what is placed, so
                            // the composition root says; the menu only draws.
                            panes: switch (view) {
                              DsView.timelines => [
                                ViewsPaneToggle(
                                  id: 'views-menu-timeline-editor',
                                  label: 'Events & ages',
                                  visible: visibility.timelineEditor,
                                  onToggle: paneVisibility.toggleTimelineEditor,
                                ),
                                ViewsPaneToggle(
                                  id: 'views-menu-timeline-reader',
                                  label: 'Reader',
                                  visible: visibility.timelineReader,
                                  onToggle: paneVisibility.toggleTimelineReader,
                                ),
                              ],
                              DsView.world => [
                                ViewsPaneToggle(
                                  id: 'views-menu-world-settings',
                                  label: 'World settings',
                                  visible: visibility.world,
                                  onToggle: paneVisibility.toggleWorld,
                                ),
                              ],
                              DsView.editor || DsView.differences => [
                                ViewsPaneToggle(
                                  id: 'views-menu-knowledge-base',
                                  label: 'Knowledge Base',
                                  visible: visibility.knowledgeBase,
                                  onToggle: paneVisibility.toggleKnowledgeBase,
                                ),
                              ],
                            },
                            pendingDifferencesCount: pendingDifferencesCount,
                          ),
                          const SizedBox(width: DsSpace.controlGap),
                          const NotificationsBellButton(),
                        ],
                        trailing: [
                          // Collaboration needs a server; without one there is
                          // nothing to sign in to.
                          if (isSupabaseConfigured) ...[
                            const AuthButton(),
                            const SizedBox(width: DsSpace.controlGap),
                          ],
                          HamburgerMenuButton(
                            entries: [
                              if (canOpenNewWindow) ...[
                                HamburgerMenuEntry.action(
                                  label: 'New Window',
                                  onSelected: () =>
                                      _openNewWindow(context, fresh: false),
                                ),
                                HamburgerMenuEntry.action(
                                  label: 'New Window as Different Account…',
                                  onSelected: () =>
                                      _openNewWindow(context, fresh: true),
                                ),
                              ],
                              // Shown with or without a server: the version is
                              // worth seeing either way, and the dialog says so
                              // itself when there is nothing to check against.
                              HamburgerMenuEntry.action(
                                label: 'Settings',
                                onSelected: () => _openAppSettings(context),
                              ),
                            ],
                          ),
                        ],
                      ),
                      Expanded(
                        child: _PaneRow(
                          rightSlotWidth:
                              (rightWidth + DsSpace.seam) * rightProgress,
                          leftSlotWidth:
                              (leftWidth + DsSpace.seam) * leftProgress,
                          onDragRight: rightProgress == 0
                              ? null
                              : (dx) => showingTimelines
                                    ? panes.dragReader(dx, available)
                                    : panes.dragPanel(dx, available),
                          onDragLeft: leftProgress == 0
                              ? null
                              : (dx) => showingWorld
                                    ? panes.dragWorld(dx, available)
                                    : panes.dragEditor(dx, available),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _SlidingSidePane(
                                progress: leftProgress,
                                panelWidth: leftWidth,
                                visible: leftVisible,
                                side: DsPaneSide.left,
                                child: switch (view) {
                                  DsView.world => const KeyedSubtree(
                                    key: Key('world-settings-pane'),
                                    child: WorldSettingsPane(),
                                  ),
                                  DsView.timelines => const KeyedSubtree(
                                    key: Key('timeline-editor-pane'),
                                    child: TimelineEditorPane(),
                                  ),
                                  DsView.editor ||
                                  DsView.differences => const SizedBox.shrink(),
                                },
                              ),
                              Expanded(
                                child: switch (view) {
                                  DsView.editor => const DsPane(
                                    key: Key('centre-workspace'),
                                    editorSurface: true,
                                    child: EditorScreen(),
                                  ),
                                  DsView.differences => const KeyedSubtree(
                                    key: Key('centre-workspace'),
                                    child: DifferencesWorkspace(),
                                  ),
                                  // The centre is the map, and only the map.
                                  DsView.timelines => const KeyedSubtree(
                                    key: Key('centre-workspace'),
                                    child: TimelineMapCanvas(),
                                  ),
                                  // The centre is the world, and only the world.
                                  DsView.world => const KeyedSubtree(
                                    key: Key('centre-workspace'),
                                    child: WorldCanvas(),
                                  ),
                                },
                              ),
                              _SlidingSidePane(
                                progress: rightProgress,
                                panelWidth: rightWidth,
                                visible: rightVisible,
                                child: switch (view) {
                                  DsView.timelines => const KeyedSubtree(
                                    key: Key('timeline-reader-pane'),
                                    child: TimelineReaderPane(),
                                  ),
                                  DsView.world => const SizedBox.shrink(),
                                  DsView.editor ||
                                  DsView.differences => KnowledgeBaseMenu(
                                    key: const Key('knowledge-base-pane'),
                                    // The gear beside the tree opens the
                                    // same App settings everything else
                                    // does, on the section that describes
                                    // the Knowledge Base it sits next to.
                                    onOpenSettings: () => _openAppSettings(
                                      context,
                                      section: AppSettingsSection.knowledgeBase,
                                    ),
                                  ),
                                },
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
/// the Knowledge Base panel, which belongs to a feature App settings is not
/// allowed to import.
void _openAppSettings(
  BuildContext context, {
  AppSettingsSection section = AppSettingsSection.updates,
}) {
  unawaited(
    showAppSettingsDialog(
      context,
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

/// Which side of the centre a pane is seated on.
enum DsPaneSide { left, right }

/// A fixed-width pane revealed through an animated slot. As the slot narrows,
/// its child stays anchored to the slot's outer edge and travels out past the
/// window's edge instead of being squeezed.
///
/// One mechanism for every view's side panes: which pane is in it, how wide it
/// is, and which side it is on are the shell's decisions rather than this
/// widget's.
class _SlidingSidePane extends StatelessWidget {
  const _SlidingSidePane({
    required this.progress,
    required this.panelWidth,
    required this.visible,
    required this.child,
    this.side = DsPaneSide.right,
  });

  final double progress;
  final double panelWidth;
  final bool visible;
  final DsPaneSide side;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final fullWidth = panelWidth + DsSpace.seam;
    final pane = SizedBox(width: panelWidth, child: child);

    return SizedBox(
      key: Key('side-pane-slide-region-${side.name}'),
      width: fullWidth * progress,
      child: ClipRect(
        child: OverflowBox(
          // A left pane slides out past the left edge, so it is its right edge
          // that stays put as the slot closes.
          alignment: side == DsPaneSide.left
              ? Alignment.topRight
              : Alignment.topLeft,
          minWidth: fullWidth,
          maxWidth: fullWidth,
          child: ExcludeSemantics(
            excluding: !visible,
            child: IgnorePointer(
              ignoring: !visible,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: side == DsPaneSide.left
                    ? [pane, const DsSeam.vertical()]
                    : [const DsSeam.vertical(), pane],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pane row, with a grab strip floated over each seam.
///
/// The seams themselves stay one pixel wide, so the panes keep every pixel of
/// their width. Resizing is done through a wider transparent strip laid over
/// each seam: it sits above both neighbours, so the whole strip catches the
/// pointer rather than only the hairline the neighbours leave exposed.
class _PaneRow extends StatelessWidget {
  const _PaneRow({
    required this.rightSlotWidth,
    required this.leftSlotWidth,
    required this.onDragRight,
    required this.onDragLeft,
    required this.child,
  });

  /// Width of the right-hand slot, seam included. Zero while it is closed.
  final double rightSlotWidth;

  /// Width of the left-hand slot, seam included. Zero while it is closed, and
  /// in every view that has no left pane.
  final double leftSlotWidth;

  /// Null while the pane on that side is closed, when there is no seam to take
  /// hold of.
  final void Function(double delta)? onDragRight;
  final void Function(double delta)? onDragLeft;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        if (onDragRight != null)
          _ResizeGrabStrip(
            right: rightSlotWidth - DsSpace.seam,
            onDrag: onDragRight!,
          ),
        if (onDragLeft != null)
          _ResizeGrabStrip(
            left: leftSlotWidth - DsSpace.seam,
            onDrag: onDragLeft!,
          ),
      ],
    );
  }
}

/// A transparent, full-height strip over one seam, which is where a pane is
/// resized from. Positioned from whichever edge its seam belongs to.
class _ResizeGrabStrip extends StatelessWidget {
  const _ResizeGrabStrip({required this.onDrag, this.left, this.right});

  /// Distance from the row's own edge to the seam this strip covers. Exactly
  /// one of the two is set.
  final double? left;
  final double? right;

  final void Function(double delta) onDrag;

  /// How far the strip reaches past the seam on either side. The seam is a
  /// hairline, so this is what there is to aim at.
  static const double _reach = 6;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left == null ? null : left! - _reach,
      right: right == null ? null : right! - _reach,
      top: 0,
      bottom: 0,
      width: DsSpace.seam + _reach * 2,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeLeftRight,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (details) => onDrag(details.delta.dx),
        ),
      ),
    );
  }
}

/// The strip across the top of the window: the menus beside the window
/// buttons, Search in the middle of the window, and the account control at the
/// far end, on the toolbar surface, closed by a seam.
class _TitleBar extends StatefulWidget {
  const _TitleBar({required this.leading, required this.trailing});

  final List<Widget> leading;
  final List<Widget> trailing;

  @override
  State<_TitleBar> createState() => _TitleBarState();
}

class _TitleBarState extends State<_TitleBar> {
  /// The bar surface itself, which its menus hang from. Held here rather than
  /// rebuilt each frame so the anchor survives a rebuild of the bar.
  final _barKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return DsMenuAnchorEdge(
      surfaceKey: _barKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: _barKey,
            height: kDsTopBarHeight,
            child: ColoredBox(
              color: context.ds.bar,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < kDsTopBarFullControlsMinWidth;

                  return Stack(
                    children: [
                      // Search centres on the window, not on whatever the two
                      // clusters leave between them, so it does not shift when
                      // the account name changes length. Compact windows keep a
                      // symmetric clear area for the native buttons and Menu.
                      Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: compact
                                ? _kCompactTopBarSearchInset
                                : 0,
                          ),
                          child: const DsSearchBar(),
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: DsSpace.s,
                          ),
                          child: Row(
                            children: [
                              Row(
                                key: const Key('title-bar-leading-controls'),
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _WindowButtonsInset(),
                                  if (!compact) ...widget.leading,
                                ],
                              ),
                              const Spacer(),
                              Row(
                                key: const Key('title-bar-trailing-controls'),
                                mainAxisSize: MainAxisSize.min,
                                children: compact
                                    ? [
                                        if (widget.trailing.isNotEmpty)
                                          widget.trailing.last,
                                      ]
                                    : widget.trailing,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          const DsSeam.horizontal(),
        ],
      ),
    );
  }
}

/// The height of the top bar. The macOS window buttons are seated inside it,
/// so `TrafficLightsOffset` is measured against this.
const double kDsTopBarHeight = 48;

/// Below this width the centred Search field and the complete menu clusters
/// no longer have enough independent space to remain visually separate.
const double kDsTopBarFullControlsMinWidth = 960;

/// Keeps compact Search clear of the macOS traffic lights. The same symmetric
/// inset also leaves the right-side hamburger control undisturbed.
const double _kCompactTopBarSearchInset = 20 + 3 * 14 + 2 * 6 + DsSpace.gap;

/// Space held clear for the macOS window buttons, which float over the top bar
/// rather than sitting in a titlebar of their own.
///
/// Windows keeps its native caption bar and needs none of this.
class _WindowButtonsInset extends StatelessWidget {
  const _WindowButtonsInset();

  /// The buttons start at `TrafficLightsOffset.defaultX` (20), are 14pt wide,
  /// and are spaced 6pt apart — then a gap before the first menu.
  static const double _width = 20 + 3 * 14 + 2 * 6 - DsSpace.s + DsSpace.gap;

  @override
  Widget build(BuildContext context) {
    // Platform, not defaultTargetPlatform: the latter reports Android under
    // `flutter test`, which would take the inset out of every golden.
    if (!Platform.isMacOS) return const SizedBox.shrink();
    return const SizedBox(key: Key('window-buttons-inset'), width: _width);
  }
}

const double _kToolbarIslandVerticalPadding = 6;

/// The formatting toolbar and its overflow menu while the Editor is active,
/// the timeline while Timelines is. Other views keep the same taller footprint
/// so the panes above do not change height when the workspace changes.
class _BottomBar extends ConsumerWidget {
  const _BottomBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(viewProvider);
    final showingEditor = view == DsView.editor;

    // The timeline runs the full width of the window rather than following the
    // workspace above it: it is the constant the view is arranged around, and
    // the design carries it edge to edge.
    if (view == DsView.timelines) {
      return const _Footer(child: TimelineStrip());
    }

    // With nothing being edited there is no toolbar, and the bar has to look
    // exactly as it did before there was one.
    final editing = showingEditor && ref.watch(editingFocusProvider) != null;

    if (editing) {
      final widths = ref.watch(paneWidthsProvider);
      final visibility = ref.watch(paneVisibilityProvider);
      final panelProgress = visibility.knowledgeBase ? 1.0 : 0.0;

      return _Footer(
        child: Row(
          children: [
            const Expanded(child: _EditingToolbarIsland()),
            SizedBox(width: (widths.panel + DsSpace.seam) * panelProgress),
          ],
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
                      children: [EditingToolbar()],
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
/// keeping the workspace and Knowledge Base islands equally short.
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
