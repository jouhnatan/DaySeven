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

  StreamSubscription<FileSystemEvent>? _watch;
  Timer? _watchDebounce;

  /// The document paths last seen on disk, so a save (which changes a file's
  /// contents but not the set of files) does not trigger a search rebuild.
  Set<String> _knownPaths = const {};

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
      await index.rebuild();

      _stopWatching();
      state.whenData((previous) => previous?.index.close());

      final tree = await kb.readTree();
      _knownPaths = _pathsIn(tree);
      state = AsyncValue.data(KbSession(kb: kb, index: index, tree: tree));

      _startWatching(kb);

      final store = await _ref.read(appStoreProvider.future);
      await store.noteKbOpened(folder);
    } catch (error, stack) {
      state = AsyncValue.error(error, stack);
    }
  }

  Future<void> refreshTree() async {
    final session = state.valueOrNull;
    if (session == null) return;
    final tree = await session.kb.readTree();
    _knownPaths = _pathsIn(tree);
    state = AsyncValue.data(session.withTree(tree));
  }

  /// Moves a document or folder into another folder, then puts search and the
  /// open document back in step with where things now are.
  Future<void> moveNode(String relativePath, String targetFolder) async {
    final session = state.valueOrNull;
    if (session == null) return;

    final destination = await session.kb.move(relativePath, targetFolder);
    if (destination == relativePath) return;

    // A moved folder takes a whole subtree of paths with it, so the index is
    // rebuilt; a single document only needs its own row repointed.
    if (relativePath.endsWith(kDocumentExtension)) {
      session.index.rename(relativePath, destination);
    } else {
      await session.index.rebuild();
    }

    await refreshTree();

    // If what moved is open — or contains what is open — reopen it where it is.
    final open = _ref.read(documentControllerProvider);
    if (open == null) return;
    if (open.relativePath == relativePath) {
      await _ref.read(documentControllerProvider.notifier).open(destination);
    } else if (p.posix.isWithin(relativePath, open.relativePath)) {
      final tail = p.posix.relative(open.relativePath, from: relativePath);
      await _ref
          .read(documentControllerProvider.notifier)
          .open(p.posix.join(destination, tail));
    }
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
    if (relative.contains(kSettingsDirName)) return;

    // A burst of events — a folder of files dropped in — settles into one read.
    _watchDebounce?.cancel();
    _watchDebounce = Timer(const Duration(milliseconds: 250), _reloadFromDisk);
  }

  Future<void> _reloadFromDisk() async {
    final session = state.valueOrNull;
    if (session == null) return;

    final tree = await session.kb.readTree();
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
    final paths = <String>{};
    void walk(List<KbNode> nodes) {
      for (final node in nodes) {
        switch (node) {
          case KbFolder():
            paths.add(node.relativePath);
            walk(node.children);
          case KbFile():
            paths.add(node.relativePath);
        }
      }
    }

    walk(nodes);
    return paths;
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
