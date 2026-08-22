/// Moving documents and their revisions between the local bundle and Postgres.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/revision.dart';

class RemoteDocumentSnapshot {
  const RemoteDocumentSnapshot({
    required this.path,
    required this.revisionId,
    required this.document,
    this.protection,
  });
  final String path;
  final String revisionId;
  final BlockDocument document;
  final DocumentProtection? protection;
}

class DocumentRepository {
  DocumentRepository({this.clientOverride});

  final SupabaseClient? clientOverride;
  SupabaseClient get client => clientOverride ?? supabase;

  /// Publishes a local document as a document row plus its first revision.
  /// The document id is the one generated locally, so the same document has one
  /// identity in the folder and in Postgres.
  Future<String> publish({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to share a document.');

    await client.from('documents').upsert({
      'id': document.id,
      'kb_id': kbId,
      'path': relativePath,
      'title': document.title,
      'deleted_at': null,
    }, onConflict: 'id');

    final revision = await client
        .from('revisions')
        .insert({
          'kb_id': kbId,
          'document_id': document.id,
          'content': document.toJson(),
          'content_hash': document.contentHash,
          'author_id': user.id,
        })
        .select('id')
        .single();

    final revisionId = revision['id'] as String;
    await client
        .from('documents')
        .update({'current_revision_id': revisionId})
        .eq('id', document.id);
    return revisionId;
  }

  /// Commits a new revision on top of the document's current one. Used when the
  /// document's own owner saves, as opposed to proposing a change.
  Future<String> commit({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to sync.');

    final current = await currentRevisionId(document.id);
    final revision = await client
        .from('revisions')
        .insert({
          'kb_id': kbId,
          'document_id': document.id,
          'parent_revision_id': current,
          'content': document.toJson(),
          'content_hash': document.contentHash,
          'author_id': user.id,
        })
        .select('id')
        .single();

    final revisionId = revision['id'] as String;
    await client
        .from('documents')
        .update({
          'current_revision_id': revisionId,
          'path': relativePath,
          'title': document.title,
        })
        .eq('id', document.id);
    return revisionId;
  }

  /// Atomically publishes an Owner or Co-Owner edit against the revision the
  /// device last observed. The server creates exactly one revision, or rejects
  /// the request if another device moved the canonical document first.
  Future<String> publishDirect({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) async {
    final revisionId = await client.rpc(
      'publish_document_directly',
      params: {
        'p_kb_id': kbId,
        'p_document_id': document.id,
        'p_relative_path': relativePath,
        'p_content': document.toJson(),
        'p_content_hash': document.contentHash,
        'p_expected_current_revision': expectedCurrentRevisionId,
      },
    );
    return revisionId as String;
  }

  /// Atomically routes an explicit save to a canonical revision or to the
  /// caller's pending proposal according to the document's protection policy.
  Future<DocumentPublishReceipt> publishChange({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) async {
    final value = await client.rpc(
      'publish_document_change',
      params: {
        'p_kb_id': kbId,
        'p_document_id': document.id,
        'p_operation': expectedCurrentRevisionId == null ? 'create' : 'update',
        'p_relative_path': relativePath,
        'p_content': document.toJson(),
        'p_content_hash': document.contentHash,
        'p_expected_current_revision': expectedCurrentRevisionId,
      },
    );
    return DocumentPublishReceipt.fromRpc(value);
  }

  Future<DocumentPublishReceipt> publishDeletion({
    required String kbId,
    required String documentId,
    required String relativePath,
    required String expectedCurrentRevisionId,
  }) async {
    final value = await client.rpc(
      'publish_document_change',
      params: {
        'p_kb_id': kbId,
        'p_document_id': documentId,
        'p_operation': 'delete',
        'p_relative_path': relativePath,
        'p_content': null,
        'p_content_hash': null,
        'p_expected_current_revision': expectedCurrentRevisionId,
      },
    );
    return DocumentPublishReceipt.fromRpc(value);
  }

  Future<DocumentProtection?> protection(String documentId) async {
    final row = await client
        .from('documents')
        .select('protection_class, minimum_publish_role')
        .eq('id', documentId)
        .maybeSingle();
    return row == null ? null : DocumentProtection.fromRow(row);
  }

  Future<DocumentProtection?> setProtection({
    required String kbId,
    required String documentId,
    DocumentProtection? protection,
  }) async {
    final value = await client.rpc(
      'set_document_protection',
      params: {
        'p_kb_id': kbId,
        'p_document_id': documentId,
        'p_protection_class': protection?.protectionClass.databaseValue,
        'p_minimum_publish_role': protection?.minimumPublishRole.databaseValue,
      },
    );
    final raw = value is List ? value.single : value;
    return DocumentProtection.fromRow(Map<String, Object?>.from(raw! as Map));
  }

  Future<String?> currentRevisionId(String documentId) async {
    final row = await client
        .from('documents')
        .select('current_revision_id')
        .eq('id', documentId)
        .maybeSingle();
    return row?['current_revision_id'] as String?;
  }

  Future<void> softDelete(String documentId) => client
      .from('documents')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', documentId);

  Future<Revision?> revision(String revisionId) async {
    final row = await client
        .from('revisions')
        .select()
        .eq('id', revisionId)
        .maybeSingle();
    return row == null ? null : Revision.fromRow(row);
  }

  Future<List<Map<String, Object?>>> documentsIn(String kbId) async {
    final rows = await client
        .from('documents')
        .select(
          'id, path, title, current_revision_id, '
          'protection_class, minimum_publish_role',
        )
        .eq('kb_id', kbId)
        .isFilter('deleted_at', null);
    return rows.cast<Map<String, Object?>>();
  }

  Future<List<RemoteDocumentSnapshot>> snapshot(String kbId) async {
    final documents = await documentsIn(kbId);
    final result = <RemoteDocumentSnapshot>[];
    for (final row in documents) {
      final revisionId = row['current_revision_id'] as String?;
      if (revisionId == null) continue;
      final current = await revision(revisionId);
      if (current == null) continue;
      result.add(
        RemoteDocumentSnapshot(
          path: row['path'] as String,
          revisionId: revisionId,
          document: current.content,
          protection: DocumentProtection.fromRow(row),
        ),
      );
    }
    return result;
  }

  Future<RemoteDocumentSnapshot?> snapshotForDocument(String documentId) async {
    final row = await client
        .from('documents')
        .select(
          'path, current_revision_id, protection_class, minimum_publish_role',
        )
        .eq('id', documentId)
        .isFilter('deleted_at', null)
        .maybeSingle();
    final revisionId = row?['current_revision_id'] as String?;
    if (row == null || revisionId == null) return null;
    final current = await revision(revisionId);
    if (current == null) return null;
    return RemoteDocumentSnapshot(
      path: row['path'] as String,
      revisionId: revisionId,
      document: current.content,
      protection: DocumentProtection.fromRow(row),
    );
  }
}

final documentRepositoryProvider = Provider((ref) => DocumentRepository());
