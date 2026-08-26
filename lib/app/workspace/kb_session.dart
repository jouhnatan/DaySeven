/// The open Knowledge Base: the bundle on disk, its search index, and the tree
/// of folders and documents, kept in step with what the filesystem is doing.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/kb/paths.dart';

class KbSession {
  const KbSession({required this.kb, required this.index, required this.tree});

  final KnowledgeBase kb;
  final SearchIndex index;
  final List<KbNode> tree;

  KbSession withTree(List<KbNode> tree) =>
      KbSession(kb: kb, index: index, tree: tree);
}

class KbController extends StateNotifier<AsyncValue<KbSession?>> {
  KbController(this._ref) : super(const AsyncValue.data(null));

  final Ref _ref;
  static const _watchDelay = Duration(milliseconds: 250);

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _watchDebounce;

  /// The document paths last seen on disk, so a save (which changes a file's
  /// contents but not the set of files) does not trigger a search rebuild.
  Set<String> _knownPaths = const {};

  /// Whether `metadata/` is shown, read once when the Knowledge Base opens.
  /// Held here so every later tree read agrees with the first one.
  bool _showMetadata = false;

  /// Opens (or creates) the bundle in a folder the user chose through the
  /// system file picker, then rebuilds the search index from the files on disk.
  Future<void> openFolder(String folder, {String? createWithName}) async {
    state = const AsyncValue.loading();
    try {
      final existing = await KnowledgeBase.existsIn(folder);
      final kb = existing
          ? await KnowledgeBase.open(folder)
          : await KnowledgeBase.create(
              folder: folder,
              name: createWithName ?? p.basename(folder),
            );

      final index = await SearchIndex.openFor(kb);

      _stopWatching();
      state.whenData((previous) => previous?.index.close());

      final store = await _ref.read(appStoreProvider.future);

      final showMetadata = await store.developerFlag(
        AppStore.showWorkspaceMetadata,
      );
      _showMetadata = showMetadata;
      index.includeMetadata = showMetadata;
      final tree = await kb.readTree(includeMetadata: showMetadata);
      _knownPaths = _pathsIn(tree);
      state = AsyncValue.data(KbSession(kb: kb, index: index, tree: tree));

      await index.rebuild();
      _startWatching(kb);
      await store.noteKbOpened(folder);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refreshTree() async {
    final session = state.valueOrNull;
    if (session == null) return;
    final tree = await session.kb.readTree(includeMetadata: _showMetadata);
    _knownPaths = _pathsIn(tree);
    state = AsyncValue.data(session.withTree(tree));
  }

  /// Creates the next available Untitled document in [folder].
  Future<String> createDocument({String folder = ''}) async {
    final session = state.valueOrNull;
    if (session == null) {
      throw const KbException('Open a Knowledge Base first.');
    }

    var title = 'Untitled';
    var suffix = 1;
    while (await _documentNameExists(session.kb, folder, title)) {
      title = 'Untitled ${++suffix}';
    }

    final path = await session.kb.createDocument(
      title: title,
      folderRelativePath: folder,
    );
    session.index.upsert(path, await session.kb.readDocument(path));
    await refreshTree();
    return path;
  }

  /// Creates one folder below [parent], applying cross-platform name rules.
  Future<String> createFolder({
    required String name,
    String parent = '',
  }) async {
    final session = state.valueOrNull;
    if (session == null) {
      throw const KbException('Open a Knowledge Base first.');
    }

    final safeName = sanitizeNodeName(name);
    final relativePath = parent.isEmpty
        ? safeName
        : p.posix.join(parent, safeName);
    if (await FileSystemEntity.type(session.kb.absolutePathFor(relativePath)) !=
        FileSystemEntityType.notFound) {
      throw KbException('A folder called "$safeName" is already there.');
    }

    await session.kb.createFolder(relativePath);
    await refreshTree();
    return relativePath;
  }

  Future<bool> _documentNameExists(
    KnowledgeBase kb,
    String folder,
    String title,
  ) async {
    for (final extension in [kDocumentExtension, kLegacyDocumentExtension]) {
      final name = '$title$extension';
      final path = folder.isEmpty ? name : p.posix.join(folder, name);
      if (await File(kb.absolutePathFor(path)).exists()) return true;
    }
    return false;
  }

  /// Moves a document or folder into another folder, then puts search and the
  /// open document back in step with where things now are.
  Future<void> moveNode(String relativePath, String targetFolder) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final documentController = _ref.read(documentControllerProvider.notifier);
    final open = _ref.read(documentControllerProvider);
    final movesOpenDocument =
        open != null && isPathAtOrBelow(open.relativePath, relativePath);
    if (movesOpenDocument) await documentController.flush();

    final destination = await session.kb.move(relativePath, targetFolder);
    if (destination == relativePath) return;

    // A moved folder takes a whole subtree of paths with it, so the index is
    // rebuilt; a single document only needs its own row repointed.
    if (isDocumentPath(relativePath)) {
      session.index.rename(relativePath, destination);
    } else {
      await session.index.rebuild();
    }

    if (open != null && movesOpenDocument) {
      documentController.relocate(
        open.relativePath,
        relocatePath(open.relativePath, from: relativePath, to: destination),
      );
    }

    final store = await _ref.read(appStoreProvider.future);
    await store.noteDocumentsMoved(
      session.kb.manifest.kbId,
      relativePath,
      destination,
    );
    _ref.read(recentEditedDocumentsRevisionProvider.notifier).state++;
    await refreshTree();
  }

  /// Renames one document and updates every local view of its path.
  Future<String> renameDocument(String relativePath, String name) async {
    final session = state.valueOrNull;
    if (session == null) {
      throw const KbException('Open a Knowledge Base first.');
    }

    final documentController = _ref.read(documentControllerProvider.notifier);
    final wasOpen =
        _ref.read(documentControllerProvider)?.relativePath == relativePath;
    if (wasOpen) await documentController.flush();

    final destination = await session.kb.renameDocument(relativePath, name);
    if (destination == relativePath) {
      final document = await session.kb.readDocument(destination);
      session.index.upsert(destination, document);
    } else {
      session.index.rename(relativePath, destination);
    }

    if (wasOpen) {
      documentController.relocate(
        relativePath,
        destination,
        title: documentTitleFromPath(destination),
      );
    }
    final store = await _ref.read(appStoreProvider.future);
    await store.noteDocumentsMoved(
      session.kb.manifest.kbId,
      relativePath,
      destination,
    );
    await store.noteDocumentEdited(session.kb.manifest.kbId, destination);
    _ref.read(recentEditedDocumentsRevisionProvider.notifier).state++;
    await refreshTree();
    return destination;
  }

  /// Deletes one document or folder and clears every local reference to it.
  Future<void> deleteNode(String relativePath) async {
    final session = state.valueOrNull;
    if (session == null) {
      throw const KbException('Open a Knowledge Base first.');
    }

    final documentController = _ref.read(documentControllerProvider.notifier);
    final open = _ref.read(documentControllerProvider);
    final deletesOpenDocument =
        open != null && isPathAtOrBelow(open.relativePath, relativePath);
    if (deletesOpenDocument) await documentController.flush();

    await session.kb.deleteNode(relativePath);

    // Once the filesystem deletion succeeds, cancel any pending editor save so
    // it cannot recreate the file that the user just removed.
    if (deletesOpenDocument) documentController.close(save: false);

    if (isDocumentPath(relativePath)) {
      session.index.remove(relativePath);
    } else {
      await session.index.rebuild();
    }

    final store = await _ref.read(appStoreProvider.future);
    await store.noteDocumentsDeleted(session.kb.manifest.kbId, relativePath);
    _ref.read(recentEditedDocumentsRevisionProvider.notifier).state++;
    await refreshTree();
  }

  /// Watches the Knowledge Base folder so a folder or document added in Finder
  /// or Explorer appears in the tree without reopening the Knowledge Base.
  void _startWatching(KnowledgeBase kb) {
    _watch?.cancel();
    try {
      _watch = Directory(kb.rootPath)
          .watch(recursive: true)
          .listen((event) => _onFileSystemEvent(kb, event));
    } on FileSystemException {
      // Some filesystems cannot be watched; the tree still refreshes on demand.
    }
  }

  void _onFileSystemEvent(KnowledgeBase kb, FileSystemEvent event) {
    // The app's own bookkeeping is not a change to the Knowledge Base.
    final relative = p.split(p.relative(event.path, from: kb.rootPath));
    if (relative.contains(kSettingsDirName) ||
        relative.contains(kMetadataDirName)) {
      return;
    }

    // A burst of events — a folder of files dropped in — settles into one read.
    _watchDebounce?.cancel();
    _watchDebounce = Timer(_watchDelay, _reloadFromDisk);
  }

  Future<void> _reloadFromDisk() async {
    final session = state.valueOrNull;
    if (session == null) return;

    final tree = await session.kb.readTree(includeMetadata: _showMetadata);
    final paths = _pathsIn(tree);

    // Documents appearing or disappearing changes what search should find;
    // an edit to an already-known document is handled when it is saved.
    if (paths.length != _knownPaths.length || !paths.containsAll(_knownPaths)) {
      _knownPaths = paths;
      await session.index.rebuild();
    }

    if (mounted) state = AsyncValue.data(session.withTree(tree));
  }

  static Set<String> _pathsIn(List<KbNode> nodes) {
    return walkKbTree(nodes).map((node) => node.relativePath).toSet();
  }

  void _stopWatching() {
    _watchDebounce?.cancel();
    _watch?.cancel();
    _watch = null;
  }

  void close() {
    _stopWatching();
    state.whenData((session) => session?.index.close());
    state = const AsyncValue.data(null);
  }

  @override
  void dispose() {
    _stopWatching();
    state.valueOrNull?.index.close();
    super.dispose();
  }
}

final kbControllerProvider =
    StateNotifierProvider<KbController, AsyncValue<KbSession?>>(
      KbController.new,
    );

final kbSessionProvider = Provider<KbSession?>(
  (ref) => ref.watch(kbControllerProvider).valueOrNull,
);

/// Recently opened Knowledge Bases, for the island's dropdown.
final recentKbPathsProvider = FutureProvider<List<String>>((ref) async {
  final store = await ref.watch(appStoreProvider.future);
  final paths = await store.recentKbPaths();
  final existing = <String>[];
  for (final path in paths) {
    if (await KnowledgeBase.existsIn(path)) existing.add(path);
  }
  return existing;
});
