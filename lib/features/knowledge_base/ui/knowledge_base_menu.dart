/// The right-side Knowledge Base menu.
///
/// Its heading sits directly on the application background. Separate islands
/// carry the folder-access dropdown and the folder-and-file structure.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/presence.dart';
import 'package:dayseven/shared/presence/peer_presence.dart';
import 'package:dayseven/shared/ui/presence_dots.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/documents/documents.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/features/knowledge_base/data/kb_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/features/knowledge_base/ui/invite_dialog.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_settings.dart';
import 'package:dayseven/features/knowledge_base/ui/name_prompt.dart';

class KnowledgeBaseMenu extends ConsumerWidget {
  const KnowledgeBaseMenu({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kbSessionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DsMenuHeader('Knowledge Base'),
        const SizedBox(height: DsSpace.islandGap),
        SizedBox(
          key: const Key('knowledge-base-access-controls'),
          height: kKnowledgeBaseControlHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Expanded(child: _KbDropdown()),
              if (session != null) ...[
                const SizedBox(width: DsSpace.islandGap),
                const KnowledgeBaseSettingsButton(),
              ],
            ],
          ),
        ),
        const SizedBox(height: DsSpace.islandGap),
        if (session != null)
          Expanded(
            child: DsIsland(
              key: const Key('knowledge-base-hierarchy'),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: _KbTree(session: session),
              ),
            ),
          )
        else
          const Spacer(),
      ],
    );
  }
}

/// The folder-access dropdown: which Knowledge Base is open, and how to open
/// another one through the system file picker.
class _KbDropdown extends ConsumerStatefulWidget {
  const _KbDropdown();

  @override
  ConsumerState<_KbDropdown> createState() => _KbDropdownState();
}

enum _KbAction { openFolder, importDocument, invite, accept }

enum _HierarchyAction { newFile, newFolder }

enum _FolderAction { newFile, newFolder, delete }

enum _DocumentAction { rename, delete }

Future<bool> _createFileIn(
  BuildContext context,
  WidgetRef ref,
  String parentFolder,
) async {
  try {
    final path = await ref
        .read(kbControllerProvider.notifier)
        .createDocument(folder: parentFolder);
    if (!context.mounted) return true;
    await ref.read(documentControllerProvider.notifier).open(path);
    if (!context.mounted) return true;
    ref.read(viewProvider.notifier).state = DsView.editor;
    return true;
  } catch (error) {
    ref
        .read(notificationStoreProvider.notifier)
        .record(DsNotificationKind.error, describeError(error));
    return false;
  }
}

Future<bool> _createFolderIn(
  BuildContext context,
  WidgetRef ref,
  String parentFolder,
) async {
  final name = await askForName(context, title: 'Folder name');
  if (name == null || name.trim().isEmpty || !context.mounted) return false;

  try {
    await ref
        .read(kbControllerProvider.notifier)
        .createFolder(name: name, parent: parentFolder);
    return true;
  } catch (error) {
    ref
        .read(notificationStoreProvider.notifier)
        .record(DsNotificationKind.error, describeError(error));
    return false;
  }
}

class _KbDropdownState extends ConsumerState<_KbDropdown> {
  Future<void> _choose() async {
    final recents = await ref.read(recentKbPathsProvider.future);
    final role = ref.read(currentUserProvider) == null
        ? null
        : ref.read(kbRoleProvider).valueOrNull;
    if (!mounted) return;

    final colors = context.ds;
    final choice = await showDsMenu<Object>(
      context: context,
      items: [
        for (final path in recents)
          DsMenuItem<Object>(
            value: path,
            height: kDsMenuItemHeight,
            child: Text(
              p.basename(path),
              style: uiTextStyle(size: 13, color: colors.text),
            ),
          ),
        if (recents.isNotEmpty) const DsMenuDivider(),
        DsMenuItem<Object>(
          value: _KbAction.openFolder,
          height: kDsMenuItemHeight,
          child: Text(
            'Open folder…',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        if (ref.read(kbSessionProvider) != null) ...[
          if (role != KbRole.reviewer)
            DsMenuItem<Object>(
              value: _KbAction.importDocument,
              height: kDsMenuItemHeight,
              child: Text(
                'Import .docx or .odt…',
                style: uiTextStyle(size: 13, color: colors.text),
              ),
            ),
          // Connection creation and deletion live behind the adjacent gear.
          // The owner's invite and a member's acceptance stay with the active
          // Knowledge Base because they are ordinary workspace actions.
          if (role != null && role != KbRole.local) ...[
            const DsMenuDivider(),
            DsMenuItem<Object>(
              value: switch (role) {
                KbRole.local => null,
                KbRole.owner => _KbAction.invite,
                KbRole.coOwner => _KbAction.invite,
                KbRole.invited => _KbAction.accept,
                KbRole.editor || KbRole.reviewer => null,
              },
              enabled: role != KbRole.editor,
              height: kDsMenuItemHeight,
              child: Text(
                switch (role) {
                  KbRole.local => '',
                  KbRole.owner => 'Invite a collaborator…',
                  KbRole.coOwner => 'Invite a collaborator…',
                  KbRole.invited => 'Accept invitation',
                  KbRole.editor => 'Your edits are proposed for review',
                  KbRole.reviewer => 'Reviewer access is read-only',
                },
                style: uiTextStyle(
                  size: 13,
                  color: role == KbRole.editor || role == KbRole.reviewer
                      ? colors.muted
                      : colors.text,
                ),
              ),
            ),
          ],
        ],
      ],
    );

    if (choice == null) return;

    switch (choice) {
      case _KbAction.openFolder:
        final folder = await getDirectoryPath(confirmButtonText: 'Open');
        if (folder == null) return;
        await ref.read(kbControllerProvider.notifier).openFolder(folder);
      case _KbAction.importDocument:
        await _importDocument();
      case _KbAction.invite:
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => InviteDialog(allowCoOwner: role == KbRole.owner),
        );
      case _KbAction.accept:
        await _guard(() async {
          final session = ref.read(kbSessionProvider);
          if (session == null) return;
          await ref
              .read(kbRepositoryProvider)
              .acceptInvitation(session.kb.manifest.kbId);
          ref.invalidate(kbRoleProvider);
        });
      case final String path:
        await ref.read(kbControllerProvider.notifier).openFolder(path);
    }
  }

  /// Runs a Knowledge Base action, showing anything that stops it.
  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.error, describeError(error));
    }
  }

  Future<void> _importDocument() async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    const typeGroup = XTypeGroup(
      label: 'Documents',
      extensions: kImportExtensions,
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;

    final path = await importDocumentInto(
      session.kb,
      File(file.path),
      folderRelativePath: '',
    );
    await ref.read(kbControllerProvider.notifier).refreshTree();
    session.index.upsert(path, await session.kb.readDocument(path));
    await ref.read(documentControllerProvider.notifier).open(path);
    ref.read(viewProvider.notifier).state = DsView.editor;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final session = ref.watch(kbSessionProvider);
    final loading = ref.watch(kbControllerProvider).isLoading;

    return DsButton(
      key: const Key('active-knowledge-base-button'),
      onPressed: loading ? null : _choose,
      highlight: colors.selection,
      height: kKnowledgeBaseControlHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      borderRadius: const BorderRadius.all(DsRadius.island),
      child: Row(
        children: [
          Expanded(
            child: Text(
              session?.kb.manifest.name ?? 'Open a folder…',
              overflow: TextOverflow.ellipsis,
              style: uiTextStyle(
                size: 13,
                weight: 600,
                color: session == null ? colors.muted : colors.text,
              ),
            ),
          ),
          Icon(Icons.expand_more, size: 16, color: colors.muted),
        ],
      ),
    );
  }
}

class _KbTree extends ConsumerWidget {
  const _KbTree({required this.session});

  final KbSession session;

  Future<void> _showRootMenu(
    BuildContext context,
    WidgetRef ref,
    Offset position,
  ) async {
    if (ref.read(kbRoleProvider).valueOrNull == KbRole.reviewer) return;
    final colors = context.ds;
    final choice = await showDsMenu<_HierarchyAction>(
      context: context,
      position: position,
      items: [
        DsMenuItem<_HierarchyAction>(
          value: _HierarchyAction.newFile,
          height: kDsMenuItemHeight,
          child: Text(
            'New file',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        DsMenuItem<_HierarchyAction>(
          value: _HierarchyAction.newFolder,
          height: kDsMenuItemHeight,
          child: Text(
            'New folder…',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
      ],
    );
    if (choice == null || !context.mounted) return;

    switch (choice) {
      case _HierarchyAction.newFile:
        await _createFileIn(context, ref, '');
      case _HierarchyAction.newFolder:
        await _createFolderIn(context, ref, '');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final readOnly = ref.watch(kbRoleProvider).valueOrNull == KbRole.reviewer;
    final tree = session.tree.isEmpty
        ? Align(
            alignment: Alignment.topLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                'No files or folders yet. Right-click to create one.',
                style: uiTextStyle(size: 12, color: context.ds.muted),
              ),
            ),
          )
        : DragTarget<String>(
            // Dropping on the panel itself, rather than on a folder, moves an
            // item back out to the top level.
            onWillAcceptWithDetails: (details) =>
                !readOnly && p.posix.dirname(details.data) != '.',
            onAcceptWithDetails: readOnly
                ? (_) {}
                : (details) => moveNode(context, ref, details.data, ''),
            builder: (context, candidate, _) => Container(
              color: candidate.isEmpty
                  ? Colors.transparent
                  : context.ds.selection.withValues(alpha: 0.4),
              child: ListView(
                key: const Key('kb-tree-list'),
                padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
                children: [
                  for (var i = 0; i < session.tree.length; i++)
                    _TreeNode(
                      node: session.tree[i],
                      ancestors: const [],
                      isLast: i == session.tree.length - 1,
                    ),
                ],
              ),
            ),
          );

    return GestureDetector(
      key: const Key('knowledge-base-root-context-target'),
      behavior: HitTestBehavior.opaque,
      onSecondaryTapUp: readOnly
          ? null
          : (details) => _showRootMenu(context, ref, details.globalPosition),
      child: tree,
    );
  }
}

/// One row of the tree, plus its children when a folder is open.
///
/// Depth is drawn rather than merely indented: a line runs down from a folder
/// through each of its children, turning in to meet each one. [ancestors]
/// carries, for every level above this row, whether that level still has
/// siblings below — which is what decides if its line continues past this row.
class _TreeNode extends ConsumerStatefulWidget {
  const _TreeNode({
    required this.node,
    required this.ancestors,
    required this.isLast,
  });

  final KbNode node;
  final List<bool> ancestors;
  final bool isLast;

  @override
  ConsumerState<_TreeNode> createState() => _TreeNodeState();
}

class _TreeNodeState extends ConsumerState<_TreeNode> {
  bool _expanded = true;
  bool _hovered = false;

  Future<void> _openDocument(String relativePath) async {
    await ref.read(documentControllerProvider.notifier).open(relativePath);
    ref.read(viewProvider.notifier).state = DsView.editor;
  }

  Future<void> _createFileInFolder(KbFolder folder) async {
    if (await _createFileIn(context, ref, folder.relativePath) && mounted) {
      setState(() => _expanded = true);
    }
  }

  /// Right-clicking a folder creates inside it, so a Knowledge Base can be
  /// organised without moving files around in Finder or Explorer.
  Future<void> _showFolderMenu(Offset position, KbFolder folder) async {
    if (ref.read(kbRoleProvider).valueOrNull == KbRole.reviewer) return;
    final colors = context.ds;

    final choice = await showDsMenu<_FolderAction>(
      context: context,
      position: position,
      items: [
        DsMenuItem<_FolderAction>(
          value: _FolderAction.newFile,
          height: kDsMenuItemHeight,
          child: Text(
            'New file here',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        DsMenuItem<_FolderAction>(
          value: _FolderAction.newFolder,
          height: kDsMenuItemHeight,
          child: Text(
            'New folder here…',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        const DsMenuDivider(),
        DsMenuItem<_FolderAction>(
          value: _FolderAction.delete,
          height: kDsMenuItemHeight,
          child: Text(
            'Delete…',
            style: uiTextStyle(
              size: 13,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _FolderAction.newFile:
        await _createFileInFolder(folder);

      case _FolderAction.newFolder:
        if (await _createFolderIn(context, ref, folder.relativePath) &&
            mounted) {
          setState(() => _expanded = true);
        }

      case _FolderAction.delete:
        await _confirmDelete(folder);
    }
  }

  Future<void> _showDocumentMenu(Offset position, KbFile file) async {
    if (ref.read(kbRoleProvider).valueOrNull == KbRole.reviewer) return;
    final colors = context.ds;
    final choice = await showDsMenu<_DocumentAction>(
      context: context,
      position: position,
      items: [
        DsMenuItem<_DocumentAction>(
          value: _DocumentAction.rename,
          height: kDsMenuItemHeight,
          child: Text(
            'Rename…',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        const DsMenuDivider(),
        DsMenuItem<_DocumentAction>(
          value: _DocumentAction.delete,
          height: kDsMenuItemHeight,
          child: Text(
            'Delete…',
            style: uiTextStyle(
              size: 13,
              color: Theme.of(context).colorScheme.error,
            ),
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case _DocumentAction.rename:
        await _renameDocument(file);
      case _DocumentAction.delete:
        await _confirmDelete(file);
    }
  }

  Future<void> _renameDocument(KbFile file) async {
    final name = await askForName(
      context,
      title: 'Document name',
      initial: file.displayName,
      actionLabel: 'Rename',
    );
    if (name == null || name.trim().isEmpty || !mounted) return;

    try {
      await ref
          .read(kbControllerProvider.notifier)
          .renameDocument(file.relativePath, name);
    } catch (error) {
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.error, describeError(error));
    }
  }

  Future<void> _confirmDelete(KbNode node) async {
    final colors = context.ds;
    final isFolder = node is KbFolder;
    final label = node is KbFile ? node.displayName : node.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => DsDialog(
        title: Text(
          'Delete “$label”?',
          style: uiTextStyle(size: 16, weight: 600, color: colors.text),
        ),
        actions: [
          DsDialogAction(
            label: 'Cancel',
            onPressed: () => Navigator.of(dialogContext).pop(false),
            tone: DsDialogActionTone.muted,
          ),
          DsDialogAction(
            label: 'Delete',
            onPressed: () => Navigator.of(dialogContext).pop(true),
            tone: DsDialogActionTone.danger,
          ),
        ],
        children: [
          Text(
            isFolder
                ? 'This permanently deletes the folder and everything inside '
                      'it from this Knowledge Base. This cannot be undone.'
                : 'This permanently deletes the Markdown file from this '
                      'Knowledge Base. This cannot be undone.',
            style: uiTextStyle(size: 13, color: colors.muted),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      for (final file in walkKbTree([node]).whereType<KbFile>()) {
        await ref
            .read(sharingControllerProvider)
            .syncDeletion(file.relativePath);
      }
      await ref
          .read(kbControllerProvider.notifier)
          .deleteNode(node.relativePath);
    } catch (error) {
      ref
          .read(notificationStoreProvider.notifier)
          .record(DsNotificationKind.error, describeError(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isFolder = node is KbFolder;
    final readOnly = ref.watch(kbRoleProvider).valueOrNull == KbRole.reviewer;

    final row = isFolder
        ? DragTarget<String>(
            onWillAcceptWithDetails: (details) =>
                !readOnly && _accepts(details.data, node.relativePath),
            onAcceptWithDetails: (details) {
              setState(() => _expanded = true);
              moveNode(context, ref, details.data, node.relativePath);
            },
            builder: (context, candidate, _) =>
                _row(context, highlighted: candidate.isNotEmpty),
          )
        : _row(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Draggable<String>(
          data: node.relativePath,
          maxSimultaneousDrags: readOnly ? 0 : 1,
          feedback: _DragLabel(
            label: node is KbFile ? node.displayName : node.name,
            isFolder: isFolder,
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: row),
          child: row,
        ),
        if (isFolder && _expanded)
          for (var i = 0; i < node.children.length; i++)
            _TreeNode(
              node: node.children[i],
              ancestors: [...widget.ancestors, !widget.isLast],
              isLast: i == node.children.length - 1,
            ),
      ],
    );
  }

  Widget _row(BuildContext context, {bool highlighted = false}) {
    final colors = context.ds;
    final node = widget.node;
    final open = ref.watch(documentControllerProvider);
    final isFolder = node is KbFolder;
    final readOnly = ref.watch(kbRoleProvider).valueOrNull == KbRole.reviewer;
    final selected = node is KbFile && open?.relativePath == node.relativePath;
    final protection = isFolder
        ? null
        : ref
              .watch(protectedDocumentsByPathProvider)
              .valueOrNull?[node.relativePath];
    // Who else is in this document right now. Keyed by path rather than by
    // document id because that is what a row has, and because a path still
    // matches when the two copies have drifted apart.
    final peers = isFolder
        ? const <PeerPresence>[]
        : ref.watch(peersByPathProvider)[node.relativePath] ?? const [];

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () {
          if (isFolder) {
            setState(() => _expanded = !_expanded);
          } else {
            _openDocument(node.relativePath);
          }
        },
        onSecondaryTapUp: switch (node) {
          KbFolder() => (details) => _showFolderMenu(
            details.globalPosition,
            node,
          ),
          KbFile() => (details) => _showDocumentMenu(
            details.globalPosition,
            node,
          ),
        },
        child: Container(
          height: _TreeGuides.rowHeight,
          decoration: BoxDecoration(
            color: highlighted
                ? colors.buttonHighlight
                : selected
                ? colors.buttonHighlight
                : _hovered
                ? colors.buttonHighlight
                : Colors.transparent,
            borderRadius: const BorderRadius.all(DsRadius.menuItem),
            border: highlighted
                ? Border.all(color: colors.muted.withValues(alpha: 0.5))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: [
              _TreeGuides(
                ancestors: widget.ancestors,
                isLast: widget.isLast,
                color: colors.muted.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 4),
              Icon(
                isFolder
                    ? (_expanded
                          ? Icons.folder_open_outlined
                          : Icons.folder_outlined)
                    : Icons.description_outlined,
                size: 14,
                color: isFolder || selected ? colors.text : colors.muted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  node is KbFile ? node.displayName : node.name,
                  overflow: TextOverflow.ellipsis,
                  style: uiTextStyle(
                    size: 13,
                    weight: isFolder || selected ? 600 : 400,
                    color: isFolder || selected ? colors.text : colors.muted,
                  ),
                ),
              ),
              if (peers.isNotEmpty) ...[
                const SizedBox(width: 6),
                PresenceDots(
                  key: ValueKey('presence-at-${node.relativePath}'),
                  peers: peers,
                ),
              ],
              if (protection != null) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message:
                      'Protected · ${protection.minimumPublishRole.label} required',
                  child: Icon(
                    Icons.shield,
                    key: ValueKey('protected-document-${node.relativePath}'),
                    size: 13,
                    color: colors.text,
                  ),
                ),
              ],
              if (node case final KbFolder folder when !readOnly)
                IconButton(
                  key: ValueKey('new-file-in-${folder.relativePath}'),
                  tooltip: 'New file in ${folder.name}',
                  onPressed: () => _createFileInFolder(folder),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: _TreeGuides.rowHeight,
                    height: _TreeGuides.rowHeight,
                  ),
                  iconSize: 16,
                  color: colors.muted,
                  hoverColor: colors.buttonHighlight,
                  icon: const Icon(Icons.add),
                )
              else
                const SizedBox(width: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Whether [dragged] can be dropped on the folder at [targetFolder]: not onto
/// itself, not into its own subtree, and not back where it already is.
bool _accepts(String dragged, String targetFolder) {
  if (dragged == targetFolder) return false;
  if (p.posix.isWithin(dragged, targetFolder)) return false;
  return p.posix.dirname(dragged) != targetFolder;
}

/// Performs the move, reporting anything that stops it.
Future<void> moveNode(
  BuildContext context,
  WidgetRef ref,
  String relativePath,
  String targetFolder,
) async {
  try {
    await ref
        .read(kbControllerProvider.notifier)
        .moveNode(relativePath, targetFolder);
  } catch (error) {
    ref
        .read(notificationStoreProvider.notifier)
        .record(DsNotificationKind.error, '$error');
  }
}

/// What follows the pointer while an item is being dragged.
class _DragLabel extends StatelessWidget {
  const _DragLabel({required this.label, required this.isFolder});

  final String label;
  final bool isFolder;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colors.island,
          borderRadius: const BorderRadius.all(DsRadius.row),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFolder ? Icons.folder_outlined : Icons.description_outlined,
              size: 14,
              color: colors.muted,
            ),
            const SizedBox(width: 6),
            Text(label, style: uiTextStyle(size: 13, color: colors.text)),
          ],
        ),
      ),
    );
  }
}

/// Draws the lines that run down from a folder to the rows beneath it.
class _TreeGuides extends StatelessWidget {
  const _TreeGuides({
    required this.ancestors,
    required this.isLast,
    required this.color,
  });

  final List<bool> ancestors;
  final bool isLast;
  final Color color;

  static const double slot = 14;
  static const double rowHeight = 26;

  @override
  Widget build(BuildContext context) {
    final depth = ancestors.length;
    // Top-level rows sit flush; there is nothing above them to connect to.
    if (depth == 0) return const SizedBox(width: 8);

    return CustomPaint(
      size: Size(8 + depth * slot, rowHeight),
      painter: _GuidePainter(
        ancestors: ancestors,
        isLast: isLast,
        color: color,
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  const _GuidePainter({
    required this.ancestors,
    required this.isLast,
    required this.color,
  });

  final List<bool> ancestors;
  final bool isLast;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..isAntiAlias = false;

    final depth = ancestors.length;
    double x(int level) => 8 + level * _TreeGuides.slot + _TreeGuides.slot / 2;
    final middle = size.height / 2;

    // Lines belonging to levels above this one, still running past this row.
    for (var level = 0; level < depth - 1; level++) {
      if (ancestors[level + 1]) {
        canvas.drawLine(
          Offset(x(level), 0),
          Offset(x(level), size.height),
          paint,
        );
      }
    }

    // This row's own connector: down from the folder, turning in to the name.
    final elbow = x(depth - 1);
    canvas.drawLine(
      Offset(elbow, 0),
      Offset(elbow, isLast ? middle : size.height),
      paint,
    );
    canvas.drawLine(
      Offset(elbow, middle),
      Offset(elbow + _TreeGuides.slot - 5, middle),
      paint,
    );
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      old.isLast != isLast ||
      old.color != color ||
      old.ancestors.length != ancestors.length;
}
