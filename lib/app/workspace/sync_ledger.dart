/// Per-local-copy knowledge of the canonical revision each file came from.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class SyncedDocument {
  const SyncedDocument({
    required this.revisionId,
    required this.contentHash,
    required this.path,
  });

  final String revisionId;
  final String contentHash;
  final String path;

  Map<String, Object?> toJson() => {
    'revisionId': revisionId,
    'contentHash': contentHash,
    'path': path,
  };

  factory SyncedDocument.fromJson(Map<String, Object?> json) => SyncedDocument(
    revisionId: json['revisionId'] as String,
    contentHash: json['contentHash'] as String,
    path: json['path'] as String,
  );
}

class SyncLedger {
  SyncLedger._(this._file, this._documents);

  final File _file;
  final Map<String, SyncedDocument> _documents;

  static Future<SyncLedger> open(KnowledgeBase kb) async {
    final file = File(p.join(kb.settingsPath, 'sync.json'));
    if (!await file.exists()) return SyncLedger._(file, {});
    try {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final documents = (json['documents'] as Map<String, Object?>? ?? const {})
          .map(
            (id, value) => MapEntry(
              id,
              SyncedDocument.fromJson(value as Map<String, Object?>),
            ),
          );
      return SyncLedger._(file, documents);
    } on Object {
      return SyncLedger._(file, {});
    }
  }

  SyncedDocument? document(String documentId) => _documents[documentId];

  Iterable<MapEntry<String, SyncedDocument>> get documents =>
      _documents.entries;

  Future<void> record({
    required BlockDocument document,
    required String revisionId,
    required String path,
  }) async {
    _documents[document.id] = SyncedDocument(
      revisionId: revisionId,
      contentHash: document.contentHash,
      path: path,
    );
    await _write();
  }

  Future<void> remove(String documentId) async {
    _documents.remove(documentId);
    await _write();
  }

  Future<void> _write() async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'documents': _documents.map(
          (id, entry) => MapEntry(id, entry.toJson()),
        ),
      }),
    );
    await temporary.rename(_file.path);
  }
}
