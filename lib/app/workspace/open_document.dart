/// The document currently being edited: its contents, whether it has unsaved
/// changes, and the debounced save that follows an edit.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/blocks/blocks.dart';

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
