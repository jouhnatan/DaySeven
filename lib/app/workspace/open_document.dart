/// The document currently being edited: its contents, whether it has unsaved
/// changes, and the debounced save that follows an edit.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

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

  OpenDocument copyWith({
    String? relativePath,
    BlockDocument? document,
    bool? dirty,
  }) => OpenDocument(
    relativePath: relativePath ?? this.relativePath,
    document: document ?? this.document,
    dirty: dirty ?? this.dirty,
  );
}

class DocumentController extends StateNotifier<OpenDocument?> {
  DocumentController(this._ref) : super(null);

  final Ref _ref;
  Timer? _saveDebounce;
  static const _saveDelay = Duration(milliseconds: 600);

  Future<void> open(String relativePath) async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;

    await flush();
    final stored = await session.kb.readDocument(relativePath);
    final fileTitle = documentTitleFromPath(relativePath);
    final document = stored.title == fileTitle
        ? stored
        : stored.copyWith(title: fileTitle);
    state = OpenDocument(
      relativePath: relativePath,
      document: document,
      dirty: false,
    );

    final store = await _ref.read(appStoreProvider.future);
    await store.noteDocumentOpened(session.kb.manifest.kbId, relativePath);
  }

  void close({bool save = true}) {
    if (save) {
      unawaited(flush());
    } else {
      _saveDebounce?.cancel();
    }
    state = null;
  }

  /// Applies an edit and schedules a save. Saving is debounced so that typing
  /// does not touch the disk on every keystroke.
  void edit(BlockDocument document) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(document: document, dirty: true);

    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () {
      unawaited(flush());
    });
  }

  /// Updates the open path without reloading the editor. Any edit made while
  /// the filesystem operation was in flight remains dirty and will be saved to
  /// the new path by its existing debounce.
  void relocate(String fromPath, String toPath, {String? title}) {
    final current = state;
    if (current == null || current.relativePath != fromPath) return;
    state = current.copyWith(
      relativePath: toPath,
      document: title == null
          ? current.document
          : current.document.copyWith(title: title),
    );
  }

  /// Writes the open document to disk and re-indexes it for search.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    final current = state;
    final session = _ref.read(kbSessionProvider);
    if (current == null || session == null || !current.dirty) return;

    await session.kb.writeDocument(current.relativePath, current.document);
    session.index.upsert(current.relativePath, current.document);
    // An edit may have arrived while the disk write was in flight. Only mark
    // the exact snapshot we wrote as clean; never overwrite the newer state.
    if (mounted && identical(state, current)) {
      state = current.copyWith(dirty: false);
    }

    final store = await _ref.read(appStoreProvider.future);
    await store.noteDocumentEdited(
      session.kb.manifest.kbId,
      current.relativePath,
    );
    _ref.read(recentEditedDocumentsRevisionProvider.notifier).state++;
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

/// An independent signal for edits that change the persisted recent list.
/// Keeping it separate from the Knowledge Base controller avoids invalidating
/// one of that controller's own downstream providers during a move or rename.
final recentEditedDocumentsRevisionProvider = StateProvider<int>((ref) => 0);

/// The five most recently saved documents in the current Knowledge Base,
/// filtered to paths that still exist on disk.
final recentEditedDocumentsProvider = FutureProvider<List<String>>((ref) async {
  ref.watch(recentEditedDocumentsRevisionProvider);
  final session = ref.watch(kbSessionProvider);
  if (session == null) return const [];
  final store = await ref.watch(appStoreProvider.future);
  final paths = await store.recentEditedDocuments(session.kb.manifest.kbId);
  final existing = <String>[];
  for (final path in paths) {
    if (await File(session.kb.absolutePathFor(path)).exists()) {
      existing.add(path);
      if (existing.length == 5) break;
    }
  }
  return existing;
});
