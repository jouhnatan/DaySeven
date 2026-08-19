/// Application state.
///
/// Deliberately small: which service is showing, which Knowledge Base is open,
/// which document is being edited, and which Knowledge Base is open. Search has
/// its own area under `lib/search/`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:dayseven/domain/blocks.dart';
import 'package:dayseven/kb/bundle.dart';
import 'package:dayseven/search/search_index.dart';

/// The left-hand rail lists services, not tools.
enum DsService { home, editor }

final serviceProvider = StateProvider<DsService>((ref) => DsService.home);

// ------------------------------------------------------------- app storage --

/// Small pieces of app-level state that belong to the installation rather than
/// to any Knowledge Base: the list of recently opened bundles.
class AppStore {
  AppStore(this._file);

  final File _file;

  static Future<AppStore> open() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return AppStore(File(p.join(dir.path, 'dayseven.json')));
  }

  Future<Map<String, Object?>> _read() async {
    if (!await _file.exists()) return {};
    try {
      return jsonDecode(await _file.readAsString()) as Map<String, Object?>;
    } on FormatException {
      return {};
    }
  }

  Future<void> _write(Map<String, Object?> data) =>
      _file.writeAsString(jsonEncode(data));

  Future<List<String>> recentKbPaths() async =>
      ((await _read())['recentKbPaths'] as List<Object?>? ?? const [])
          .cast<String>();

  Future<void> noteKbOpened(String path) async {
    final data = await _read();
    final list =
        (data['recentKbPaths'] as List<Object?>? ?? const [])
            .cast<String>()
            .where((e) => e != path)
            .toList()
          ..insert(0, path);
    data['recentKbPaths'] = list.take(10).toList();
    await _write(data);
  }

  Future<Map<String, double>> paneWidths() async {
    final raw =
        (await _read())['paneWidths'] as Map<String, Object?>? ?? const {};
    return {
      for (final entry in raw.entries)
        if (entry.value is num) entry.key: (entry.value! as num).toDouble(),
    };
  }

  Future<void> setPaneWidth(String pane, double width) async {
    final data = await _read();
    final widths = (data['paneWidths'] as Map<String, Object?>? ?? {});
    widths[pane] = width;
    data['paneWidths'] = widths;
    await _write(data);
  }

  /// Recent documents are tracked per Knowledge Base, keyed by its id, so
  /// moving a bundle between machines does not lose the list.
  Future<List<String>> recentDocuments(String kbId) async =>
      (((await _read())['recentDocuments'] as Map<String, Object?>? ??
                      const {})[kbId]
                  as List<Object?>? ??
              const [])
          .cast<String>();

  Future<void> noteDocumentOpened(String kbId, String relativePath) async {
    final data = await _read();
    final all = (data['recentDocuments'] as Map<String, Object?>? ?? {});
    final list =
        (all[kbId] as List<Object?>? ?? const [])
            .cast<String>()
            .where((e) => e != relativePath)
            .toList()
          ..insert(0, relativePath);
    all[kbId] = list.take(20).toList();
    data['recentDocuments'] = all;
    await _write(data);
  }
}

final appStoreProvider = FutureProvider<AppStore>((ref) => AppStore.open());

/// How wide the two side panes are. The editor takes whatever is left, so the
/// panes are what the user drags. Persisted, so a window comes back the way it
/// was left.
class PaneWidths {
  const PaneWidths({this.rail = 140, this.panel = 248});

  final double rail;
  final double panel;

  static const double minRail = 104;
  static const double maxRail = 280;
  static const double minPanel = 180;
  static const double maxPanel = 560;

  /// The editor never collapses to nothing, however far a handle is dragged.
  static const double minEditor = 320;

  PaneWidths copyWith({double? rail, double? panel}) =>
      PaneWidths(rail: rail ?? this.rail, panel: panel ?? this.panel);
}

class PaneWidthsController extends StateNotifier<PaneWidths> {
  PaneWidthsController(this._ref) : super(const PaneWidths()) {
    _restore();
  }

  final Ref _ref;

  Future<void> _restore() async {
    final store = await _ref.read(appStoreProvider.future);
    final widths = await store.paneWidths();
    if (!mounted) return;
    state = PaneWidths(
      rail: widths['rail'] ?? state.rail,
      panel: widths['panel'] ?? state.panel,
    );
  }

  /// [available] is the width the three panes and their handles share, so a
  /// drag can be stopped before the editor is squeezed out.
  void dragRail(double delta, double available) {
    final headroom = available - state.panel - PaneWidths.minEditor;
    final rail = (state.rail + delta)
        .clamp(PaneWidths.minRail, PaneWidths.maxRail)
        .clamp(
          PaneWidths.minRail,
          headroom.clamp(PaneWidths.minRail, PaneWidths.maxRail),
        );
    _set(state.copyWith(rail: rail));
  }

  void dragPanel(double delta, double available) {
    final headroom = available - state.rail - PaneWidths.minEditor;
    final panel = (state.panel - delta)
        .clamp(PaneWidths.minPanel, PaneWidths.maxPanel)
        .clamp(
          PaneWidths.minPanel,
          headroom.clamp(PaneWidths.minPanel, PaneWidths.maxPanel),
        );
    _set(state.copyWith(panel: panel));
  }

  void _set(PaneWidths widths) {
    state = widths;
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 400), () async {
      final store = await _ref.read(appStoreProvider.future);
      await store.setPaneWidth('rail', state.rail);
      await store.setPaneWidth('panel', state.panel);
    });
  }

  Timer? _saveDebounce;

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

final paneWidthsProvider =
    StateNotifierProvider<PaneWidthsController, PaneWidths>(
      PaneWidthsController.new,
    );

// ------------------------------------------------------- open knowledge base --

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

// ------------------------------------------------------------ open document --

class OpenDocument {
  const OpenDocument({
    required this.relativePath,
    required this.document,
    required this.dirty,
  });

  final String relativePath;
  final BlockDocument document;

  /// True between an edit and the debounced save that follows it.
  final bool dirty;

  OpenDocument copyWith({BlockDocument? document, bool? dirty}) => OpenDocument(
    relativePath: relativePath,
    document: document ?? this.document,
    dirty: dirty ?? this.dirty,
  );
}

class DocumentController extends StateNotifier<OpenDocument?> {
  DocumentController(this._ref) : super(null);

  final Ref _ref;
  Timer? _saveDebounce;

  Future<void> open(String relativePath) async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;

    await flush();
    final document = await session.kb.readDocument(relativePath);
    state = OpenDocument(
      relativePath: relativePath,
      document: document,
      dirty: false,
    );

    final store = await _ref.read(appStoreProvider.future);
    await store.noteDocumentOpened(session.kb.manifest.kbId, relativePath);
  }

  void close() {
    unawaited(flush());
    state = null;
  }

  /// Applies an edit and schedules a save. Saving is debounced so that typing
  /// does not touch the disk on every keystroke.
  void edit(BlockDocument document) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(document: document, dirty: true);

    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 600), () {
      unawaited(flush());
    });
  }

  /// Writes the open document to disk and re-indexes it for search.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    final current = state;
    final session = _ref.read(kbSessionProvider);
    if (current == null || session == null || !current.dirty) return;

    await session.kb.writeDocument(current.relativePath, current.document);
    session.index.upsert(current.relativePath, current.document);
    if (mounted) state = current.copyWith(dirty: false);
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}

final documentControllerProvider =
    StateNotifierProvider<DocumentController, OpenDocument?>(
      DocumentController.new,
    );

/// Recently opened documents in the current Knowledge Base, filtered to those
/// that still exist on disk.
final recentDocumentsProvider = FutureProvider<List<String>>((ref) async {
  final session = ref.watch(kbSessionProvider);
  if (session == null) return const [];
  final store = await ref.watch(appStoreProvider.future);
  final paths = await store.recentDocuments(session.kb.manifest.kbId);
  final existing = <String>[];
  for (final path in paths) {
    if (await File(session.kb.absolutePathFor(path)).exists()) {
      existing.add(path);
    }
  }
  return existing;
});

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
