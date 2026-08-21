/// Small pieces of state that belong to the installation rather than to any
/// Knowledge Base: recently opened bundles, recently opened documents, and the
/// width the side panes were left at.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:dayseven/shared/kb/paths.dart';

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

  /// Visibility of optional shell panes. Unknown and malformed values are
  /// ignored so older or hand-edited settings keep the default layout.
  Future<Map<String, bool>> paneVisibility() async {
    final raw = (await _read())['paneVisibility'];
    if (raw is! Map<String, Object?>) return {};
    return {
      for (final entry in raw.entries)
        if (entry.value is bool) entry.key: entry.value! as bool,
    };
  }

  Future<void> setPaneVisibility(String pane, bool visible) async {
    final data = await _read();
    final raw = data['paneVisibility'];
    final visibility = raw is Map<String, Object?>
        ? Map<String, Object?>.from(raw)
        : <String, Object?>{};
    visibility[pane] = visible;
    data['paneVisibility'] = visibility;
    await _write(data);
  }

  /// Recent documents are tracked per Knowledge Base, keyed by its id, so
  /// moving a bundle between machines does not lose the list.
  Future<List<String>> recentDocuments(String kbId) async =>
      _documentList('recentDocuments', kbId);

  Future<List<String>> recentEditedDocuments(String kbId) async =>
      _documentList('recentEditedDocuments', kbId);

  Future<void> noteDocumentOpened(String kbId, String relativePath) async {
    await _updateDocumentLists(['recentDocuments'], kbId, (current) {
      final next = current.where((path) => path != relativePath).toList()
        ..insert(0, relativePath);
      return next.take(20).toList();
    });
  }

  Future<void> noteDocumentEdited(String kbId, String relativePath) async {
    await _updateDocumentLists(['recentEditedDocuments'], kbId, (current) {
      final next = current.where((path) => path != relativePath).toList()
        ..insert(0, relativePath);
      return next.take(20).toList();
    });
  }

  /// Repoints recent-document entries after a file or a containing folder is
  /// moved. Their order is preserved and duplicate paths are collapsed.
  Future<void> noteDocumentsMoved(
    String kbId,
    String fromPath,
    String toPath,
  ) async {
    await _updateDocumentLists(
      ['recentDocuments', 'recentEditedDocuments'],
      kbId,
      (current) {
        final moved = <String>{
          for (final path in current)
            relocatePath(path, from: fromPath, to: toPath),
        };
        return moved.toList();
      },
    );
  }

  /// Removes a deleted document, or every document below a deleted folder,
  /// from the recent list for this Knowledge Base.
  Future<void> noteDocumentsDeleted(String kbId, String deletedPath) async {
    await _updateDocumentLists(
      ['recentDocuments', 'recentEditedDocuments'],
      kbId,
      (current) =>
          current.where((path) => !isPathAtOrBelow(path, deletedPath)).toList(),
    );
  }

  Future<List<String>> _documentList(String key, String kbId) async {
    final data = await _read();
    final all = data[key] as Map<String, Object?>? ?? const {};
    return (all[kbId] as List<Object?>? ?? const []).cast<String>();
  }

  Future<void> _updateDocumentLists(
    List<String> keys,
    String kbId,
    List<String> Function(List<String> current) update,
  ) async {
    final data = await _read();
    for (final key in keys) {
      final all = (data[key] as Map<String, Object?>? ?? {});
      final current = (all[kbId] as List<Object?>? ?? const []).cast<String>();
      all[kbId] = update(current);
      data[key] = all;
    }
    await _write(data);
  }
}

final appStoreProvider = FutureProvider<AppStore>((ref) => AppStore.open());
