/// Per-local-copy knowledge of the canonical revision each file came from.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class SyncedDocument {
  const SyncedDocument({
    required this.revisionId,
    required this.contentHash,
    required this.path,
    this.protection,
  });

  final String revisionId;
  final String contentHash;
  final String path;
  final DocumentProtection? protection;

  Map<String, Object?> toJson() => {
    'revisionId': revisionId,
    'contentHash': contentHash,
    'path': path,
    'protectionClass': protection?.protectionClass.databaseValue,
    'minimumPublishRole': protection?.minimumPublishRole.databaseValue,
  };

  factory SyncedDocument.fromJson(Map<String, Object?> json) {
    final protection = DocumentProtection.fromRow({
      'protection_class': json['protectionClass'],
      'minimum_publish_role': json['minimumPublishRole'],
    });
    return SyncedDocument(
      revisionId: json['revisionId'] as String,
      contentHash: json['contentHash'] as String,
      path: json['path'] as String,
      protection: protection,
    );
  }
}

/// The last canonical revision and path a `.unearth` object was seen at.
class SyncedObject {
  const SyncedObject({
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

  factory SyncedObject.fromJson(Map<String, Object?> json) => SyncedObject(
    revisionId: json['revisionId'] as String,
    contentHash: json['contentHash'] as String,
    path: json['path'] as String,
  );
}

class SyncLedger {
  SyncLedger._(this._file, this._documents, this._objects);

  final File _file;
  final Map<String, SyncedDocument> _documents;
  final Map<String, SyncedObject> _objects;

  static Future<SyncLedger> open(KnowledgeBase kb) async {
    final file = File(p.join(kb.settingsPath, 'sync.json'));
    if (!await file.exists()) return SyncLedger._(file, {}, {});
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
      final objects = (json['objects'] as Map<String, Object?>? ?? const {})
          .map(
            (id, value) => MapEntry(
              id,
              SyncedObject.fromJson(value as Map<String, Object?>),
            ),
          );
      return SyncLedger._(file, documents, objects);
    } on Object {
      return SyncLedger._(file, {}, {});
    }
  }

  SyncedDocument? document(String documentId) => _documents[documentId];

  Iterable<MapEntry<String, SyncedDocument>> get documents =>
      _documents.entries;

  SyncedObject? object(String objectId) => _objects[objectId];

  Iterable<MapEntry<String, SyncedObject>> get objects => _objects.entries;

  Future<void> record({
    required BlockDocument document,
    required String revisionId,
    required String path,
    DocumentProtection? protection,
  }) async {
    _documents[document.id] = SyncedDocument(
      revisionId: revisionId,
      contentHash: document.contentHash,
      path: path,
      protection: protection,
    );
    await _write();
  }

  Future<void> remove(String documentId) async {
    _documents.remove(documentId);
    await _write();
  }

  Future<void> recordObject({
    required String objectId,
    required String revisionId,
    required String contentHash,
    required String path,
  }) async {
    _objects[objectId] = SyncedObject(
      revisionId: revisionId,
      contentHash: contentHash,
      path: path,
    );
    await _write();
  }

  Future<void> removeObject(String objectId) async {
    _objects.remove(objectId);
    await _write();
  }

  Future<void> _write() async {
    await _file.parent.create(recursive: true);
    final temporary = File('${_file.path}.tmp');
    await temporary.writeAsString(
      const JsonEncoder.withIndent(' ').convert({
        'version': 2,
        'documents': _documents.map(
          (id, entry) => MapEntry(id, entry.toJson()),
        ),
        'objects': _objects.map((id, entry) => MapEntry(id, entry.toJson())),
      }),
    );
    await temporary.rename(_file.path);
  }
}
