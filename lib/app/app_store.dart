/// Small pieces of state that belong to the installation rather than to any
/// Knowledge Base: recently opened bundles, recently opened documents, and the
/// width the side panes were left at.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
