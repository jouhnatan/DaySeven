/// Moving Knowledge Base objects and their revisions between the local bundle
/// and Postgres.
///
/// Objects are kind-blind here on purpose: the World feature owns what a
/// `world` means, and the server stores the `.unearth` JSON as it arrives. The
/// one thing shared code must agree on is the content hash, which is why
/// [canonicalObjectHash] sorts keys before hashing — two machines must call
/// the same content the same hash even if they built their maps in a
/// different order.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';

/// A current object in a Knowledge Base, with the content of its revision.
class RemoteObjectSnapshot {
  const RemoteObjectSnapshot({
    required this.id,
    required this.kind,
    required this.path,
    required this.revisionId,
    required this.content,
    required this.contentHash,
  });

  final String id;
  final String kind;
  final String path;
  final String revisionId;
  final Map<String, Object?> content;
  final String contentHash;
}

class ObjectRepository {
  ObjectRepository({this.clientOverride});

  final SupabaseClient? clientOverride;
  SupabaseClient get client => clientOverride ?? supabase;

  /// Every live object in a Knowledge Base, with its current content.
  ///
  /// Two queries regardless of how many objects there are, mirroring
  /// [DocumentRepository.snapshot]. A server that predates object sync has no
  /// `kb_objects` relation; it answers as if there were no remote objects, so
  /// document sync still works for a client that learned about objects first.
  Future<List<RemoteObjectSnapshot>> snapshot(String kbId) async {
    try {
      return await _snapshot(kbId);
    } on PostgrestException catch (error) {
      if (isObjectsUnavailable(error)) return const [];
      rethrow;
    }
  }

  Future<List<RemoteObjectSnapshot>> _snapshot(String kbId) async {
    final objectRows =
        (await client
                .from('kb_objects')
                .select('id, kind, path, current_revision_id')
                .eq('kb_id', kbId)
                .isFilter('deleted_at', null))
            .cast<Map<String, Object?>>();

    final revisionIds = <String>[
      for (final row in objectRows)
        if (row['current_revision_id'] case final String id) id,
    ];

    const chunkSize = 100;
    final revisions = <String, Map<String, Object?>>{};
    for (var start = 0; start < revisionIds.length; start += chunkSize) {
      final end = start + chunkSize > revisionIds.length
          ? revisionIds.length
          : start + chunkSize;
      final rows =
          (await client
                  .from('kb_object_revisions')
                  .select('id, content, content_hash')
                  .inFilter('id', revisionIds.sublist(start, end)))
              .cast<Map<String, Object?>>();
      for (final row in rows) {
        revisions[row['id'] as String] = row;
      }
    }

    final snapshots = <RemoteObjectSnapshot>[];
    for (final row in objectRows) {
      final revisionId = row['current_revision_id'] as String?;
      if (revisionId == null) continue;
      final revision = revisions[revisionId];
      if (revision == null) continue;
      final rawContent = revision['content'];
      if (rawContent is! Map) continue;
      snapshots.add(
        RemoteObjectSnapshot(
          id: row['id'] as String,
          kind: row['kind'] as String,
          path: row['path'] as String,
          revisionId: revisionId,
          content: Map<String, Object?>.from(rawContent),
          contentHash: revision['content_hash'] as String,
        ),
      );
    }
    return snapshots;
  }

  /// Publishes one object revision against the revision the caller last
  /// observed. The server creates exactly one revision, or answers with a
  /// `40001` conflict if the object moved on.
  Future<String> publish({
    required String kbId,
    required String objectId,
    required String kind,
    required String path,
    required String title,
    required Map<String, Object?> content,
    required String contentHash,
    required String? expectedCurrentRevisionId,
  }) async {
    final value = await client.rpc(
      'publish_object',
      params: {
        'p_kb_id': kbId,
        'p_object_id': objectId,
        'p_kind': kind,
        'p_path': path,
        'p_title': title,
        'p_content': content,
        'p_content_hash': contentHash,
        'p_expected_current_revision': expectedCurrentRevisionId,
      },
    );
    final raw = value is List ? value.single : value;
    final result = Map<String, Object?>.from(raw! as Map);
    return result['revision_id'] as String;
  }
}

/// True when the server has no object schema yet — PostgREST reports a missing
/// relation as `PGRST205`, and a raw Postgres error as `42P01`. A build that
/// speaks objects before the database does must not break document sync.
bool isObjectsUnavailable(Object error) =>
    error is PostgrestException &&
    (error.code == 'PGRST205' || error.code == '42P01');

/// A stable hash of object content: keys sorted at every depth before the
/// JSON is encoded, so insertion order can never make two equal objects look
/// different.
String canonicalObjectHash(Map<String, Object?> content) =>
    sha256.convert(utf8.encode(jsonEncode(_canonicalJson(content)))).toString();

Object? _canonicalJson(Object? value) {
  if (value is Map) {
    final entries = <MapEntry<String, Object?>>[
      for (final entry in value.entries)
        MapEntry(entry.key.toString(), _canonicalJson(entry.value)),
    ]..sort((a, b) => a.key.compareTo(b.key));
    return {for (final entry in entries) entry.key: entry.value};
  }
  if (value is Iterable) {
    return [for (final item in value) _canonicalJson(item)];
  }
  return value;
}

final objectRepositoryProvider = Provider((ref) => ObjectRepository());
