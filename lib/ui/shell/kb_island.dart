/// The right-hand Knowledge Base panel.
///
/// A rounded "island" carries the folder-access dropdown, separated from the
/// editor by a gap on the application background. Below it, the Knowledge
/// Base's folder-and-file structure.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/app/state.dart';
import 'package:dayseven/app/theme.dart';
import 'package:dayseven/convert/documents.dart';
import 'package:dayseven/kb/bundle.dart';
import 'package:dayseven/auth/auth_repository.dart';
import 'package:dayseven/sync/sharing.dart';
import 'package:dayseven/sync/supabase.dart';
import 'package:dayseven/ui/shell/invite_dialog.dart';
import 'package:dayseven/ui/shell/name_prompt.dart';
import 'package:dayseven/ui/shell/shell.dart';

class KbIsland extends ConsumerWidget {
  const KbIsland({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(kbSessionProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The band naming the open Knowledge Base, kept as its own island.
        const _KbDropdown(),
        const SizedBox(height: DsSpace.islandGap),
        if (session != null)
          Expanded(
            child: DsIsland(
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

/// Menu values that are actions rather than a Knowledge Base path.
const String _actionOpenFolder = ':open';
const String _actionNewDocument = ':new';
const String _actionImportDocument = ':import';
const String _actionNewFolder = ':newFolder';
const String _actionShare = ':share';
const String _actionInvite = ':invite';
const String _actionAccept = ':accept';

class _KbDropdownState extends ConsumerState<_KbDropdown> {
  bool _hovered = false;

  Future<void> _choose() async {
    final recents = await ref.read(recentKbPathsProvider.future);
    final role = ref.read(currentUserProvider) == null
        ? null
        : ref.read(kbRoleProvider).valueOrNull;
    if (!mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;

    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        box.localToGlobal(Offset.zero, ancestor: overlay),
        box.localToGlobal(box.size.bottomRight(Offset.zero), ancestor: overlay),
      ),
      Offset.zero & overlay.size,
    );

    final colors = context.ds;
    final choice = await showMenu<String>(
      context: context,
      position: position,
      color: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.control),
        side: BorderSide(color: colors.border),
      ),
      items: [
        for (final path in recents)
          PopupMenuItem<String>(
            value: path,
            height: 34,
            child: Text(
              p.basename(path),
              style: aleo(size: 13, color: colors.text),
            ),
          ),
        if (recents.isNotEmpty) const PopupMenuDivider(height: 1),
        PopupMenuItem<String>(
          value: _actionOpenFolder,
          height: 34,
          child: Text(
            'Open folder…',
            style: aleo(size: 13, color: colors.text),
          ),
        ),
        if (ref.read(kbSessionProvider) != null) ...[
          PopupMenuItem<String>(
            value: _actionNewDocument,
            height: 34,
            child: Text(
              'New document',
              style: aleo(size: 13, color: colors.text),
            ),
          ),
          PopupMenuItem<String>(
            value: _actionNewFolder,
            height: 34,
            child: Text(
              'New folder…',
              style: aleo(size: 13, color: colors.text),
            ),
          ),
          PopupMenuItem<String>(
            value: _actionImportDocument,
            height: 34,
            child: Text(
              'Import .docx or .odt…',
              style: aleo(size: 13, color: colors.text),
            ),
          ),
          // Sharing belongs to the Knowledge Base, so it lives here rather
          // than with the account. Only shown once signed in.
          if (role != null) ...[
            const PopupMenuDivider(height: 1),
            PopupMenuItem<String>(
              value: switch (role) {
                KbRole.local => _actionShare,
                KbRole.owner => _actionInvite,
                KbRole.invited => _actionAccept,
                KbRole.editor => '',
              },
              enabled: role != KbRole.editor,
              height: 34,
              child: Text(
                switch (role) {
                  KbRole.local => 'Share this Knowledge Base',
                  KbRole.owner => 'Invite a collaborator…',
                  KbRole.invited => 'Accept invitation',
                  KbRole.editor => 'Your edits are proposed for review',
                },
                style: aleo(
                  size: 13,
                  color: role == KbRole.editor ? colors.muted : colors.text,
                ),
              ),
            ),
          ],
        ],
      ],
    );

    if (choice == null) return;

    switch (choice) {
      case _actionOpenFolder:
        final folder = await getDirectoryPath(confirmButtonText: 'Open');
        if (folder == null) return;
        await ref.read(kbControllerProvider.notifier).openFolder(folder);
      case _actionNewDocument:
        await _createDocument();
      case _actionNewFolder:
        await _createFolder();
      case _actionImportDocument:
        await _importDocument();
      case _actionShare:
        await _guard(() => ref.read(sharingControllerProvider).shareOpenKb());
      case _actionInvite:
        if (!mounted) return;
        await showDialog<void>(
          context: context,
          builder: (_) => const InviteDialog(),
        );
      case _actionAccept:
        await _guard(() async {
          final session = ref.read(kbSessionProvider);
          if (session == null) return;
          await ref
              .read(kbRepositoryProvider)
              .acceptInvitation(session.kb.manifest.kbId);
          ref.invalidate(kbRoleProvider);
        });
      default:
        await ref.read(kbControllerProvider.notifier).openFolder(choice);
    }
  }

  /// Runs a Knowledge Base action, showing anything that stops it.
  Future<void> _guard(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await action();
    } catch (error) {
      messenger?.showSnackBar(SnackBar(content: Text(describeError(error))));
    }
  }

  Future<void> _createDocument({String inFolder = ''}) async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    // Untitled until the user types a title into the document itself.
    var title = 'Untitled';
    var attempt = 1;
    String pathFor(String t) => inFolder.isEmpty
        ? '$t$kDocumentExtension'
        : '$inFolder/$t$kDocumentExtension';

    while (await File(session.kb.absolutePathFor(pathFor(title))).exists()) {
      attempt++;
      title = 'Untitled $attempt';
    }

    final path = await session.kb.createDocument(
      title: title,
      folderRelativePath: inFolder,
    );
    await ref.read(kbControllerProvider.notifier).refreshTree();
    await ref.read(documentControllerProvider.notifier).open(path);
    ref.read(serviceProvider.notifier).state = DsService.editor;
  }

  Future<void> _createFolder({String inFolder = ''}) async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    final name = await askForName(context, title: 'Folder name');
    if (name == null || name.trim().isEmpty) return;

    final relative = inFolder.isEmpty
        ? name.trim()
        : '$inFolder/${name.trim()}';
    await session.kb.createFolder(relative);
    await ref.read(kbControllerProvider.notifier).refreshTree();
  }

  Future<void> _importDocument({String inFolder = ''}) async {
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
      folderRelativePath: inFolder,
    );
    await ref.read(kbControllerProvider.notifier).refreshTree();
    session.index.upsert(path, await session.kb.readDocument(path));
    await ref.read(documentControllerProvider.notifier).open(path);
    ref.read(serviceProvider.notifier).state = DsService.editor;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final session = ref.watch(kbSessionProvider);
    final loading = ref.watch(kbControllerProvider).isLoading;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: loading ? null : _choose,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 90),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _hovered ? colors.selection : colors.island,
            borderRadius: const BorderRadius.all(DsRadius.island),
            border: Border.all(color: colors.border, width: 1),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  session?.kb.manifest.name ?? 'Knowledge Base',
                  overflow: TextOverflow.ellipsis,
                  style: aleo(
                    size: 13,
                    weight: 600,
                    color: session == null ? colors.muted : colors.text,
                  ),
                ),
              ),
              Icon(Icons.expand_more, size: 16, color: colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class _KbTree extends ConsumerWidget {
  const _KbTree({required this.session});

  final KbSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (session.tree.isEmpty) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Text(
            'No folders yet.',
            style: aleo(size: 12, color: context.ds.muted),
          ),
        ),
      );
    }

    // Dropping on the panel itself, rather than on a folder, moves an item
    // back out to the top level.
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          p.posix.dirname(details.data) != '.',
      onAcceptWithDetails: (details) =>
          moveNode(context, ref, details.data, ''),
      builder: (context, candidate, _) => Container(
        color: candidate.isEmpty
            ? Colors.transparent
            : context.ds.selection.withValues(alpha: 0.4),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 4),
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
    ref.read(serviceProvider.notifier).state = DsService.editor;
  }

  /// Right-clicking a folder creates inside it, so a Knowledge Base can be
  /// organised without moving files around in Finder or Explorer.
  Future<void> _showFolderMenu(Offset position, KbFolder folder) async {
    final colors = context.ds;
    final session = ref.read(kbSessionProvider);
    if (session == null) return;

    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy,
        position.dx,
        position.dy,
      ),
      color: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.control),
        side: BorderSide(color: colors.border),
      ),
      items: [
        PopupMenuItem<String>(
          value: 'document',
          height: 34,
          child: Text(
            'New document here',
            style: aleo(size: 13, color: colors.text),
          ),
        ),
        PopupMenuItem<String>(
          value: 'folder',
          height: 34,
          child: Text(
            'New folder here…',
            style: aleo(size: 13, color: colors.text),
          ),
        ),
      ],
    );
    if (choice == null || !mounted) return;

    switch (choice) {
      case 'document':
        var title = 'Untitled';
        var attempt = 1;
        while (await File(
          session.kb.absolutePathFor(
            '${folder.relativePath}/$title$kDocumentExtension',
          ),
        ).exists()) {
          attempt++;
          title = 'Untitled $attempt';
        }
        final path = await session.kb.createDocument(
          title: title,
          folderRelativePath: folder.relativePath,
        );
        await ref.read(kbControllerProvider.notifier).refreshTree();
        await ref.read(documentControllerProvider.notifier).open(path);
        ref.read(serviceProvider.notifier).state = DsService.editor;

      case 'folder':
        if (!mounted) return;
        final name = await askForName(context, title: 'Folder name');
        if (name == null || name.trim().isEmpty) return;
        await session.kb.createFolder('${folder.relativePath}/${name.trim()}');
        await ref.read(kbControllerProvider.notifier).refreshTree();
    }
  }

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final isFolder = node is KbFolder;

    final row = isFolder
        ? DragTarget<String>(
            onWillAcceptWithDetails: (details) =>
                _accepts(details.data, node.relativePath),
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
    final selected = node is KbFile && open?.relativePath == node.relativePath;

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
        onSecondaryTapUp: node is KbFolder
            ? (details) => _showFolderMenu(details.globalPosition, node)
            : null,
        child: Container(
          height: _TreeGuides.rowHeight,
          decoration: BoxDecoration(
            color: highlighted
                ? colors.selection
                : selected
                ? colors.selection
                : _hovered
                ? colors.selection.withValues(alpha: 0.5)
                : Colors.transparent,
            borderRadius: const BorderRadius.all(DsRadius.row),
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
                  style: aleo(
                    size: 13,
                    weight: isFolder || selected ? 600 : 400,
                    color: isFolder || selected ? colors.text : colors.muted,
                  ),
                ),
              ),
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
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await ref
        .read(kbControllerProvider.notifier)
        .moveNode(relativePath, targetFolder);
  } catch (error) {
    messenger?.showSnackBar(SnackBar(content: Text('$error')));
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
            Text(label, style: aleo(size: 13, color: colors.text)),
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
