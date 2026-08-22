/// Moving documents and their revisions between the local bundle and Postgres.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/revision.dart';

class RemoteDocumentSnapshot {
  const RemoteDocumentSnapshot({
    required this.path,
    required this.revisionId,
    required this.document,
  });
  final String path;
  final String revisionId;
  final BlockDocument document;
}

class DocumentRepository {
  /// Publishes a local document as a document row plus its first revision.
  /// The document id is the one generated locally, so the same document has one
  /// identity in the folder and in Postgres.
  Future<String> publish({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to share a document.');

    await supabase.from('documents').upsert({
      'id': document.id,
      'kb_id': kbId,
      'path': relativePath,
      'title': document.title,
      'deleted_at': null,
    }, onConflict: 'id');

    final revision = await supabase
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
    await supabase
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
    final user = supabase.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to sync.');

    final current = await currentRevisionId(document.id);
    final revision = await supabase
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
    await supabase
        .from('documents')
        .update({
          'current_revision_id': revisionId,
          'path': relativePath,
          'title': document.title,
        })
        .eq('id', document.id);
    return revisionId;
  }

  Future<String?> currentRevisionId(String documentId) async {
    final row = await supabase
        .from('documents')
        .select('current_revision_id')
        .eq('id', documentId)
        .maybeSingle();
    return row?['current_revision_id'] as String?;
  }

  Future<void> softDelete(String documentId) => supabase
      .from('documents')
      .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
      .eq('id', documentId);

  Future<Revision?> revision(String revisionId) async {
    final row = await supabase
        .from('revisions')
        .select()
        .eq('id', revisionId)
        .maybeSingle();
    return row == null ? null : Revision.fromRow(row);
  }

  Future<List<Map<String, Object?>>> documentsIn(String kbId) async {
    final rows = await supabase
        .from('documents')
        .select('id, path, title, current_revision_id')
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
        ),
      );
    }
    return result;
  }
}

final documentRepositoryProvider = Provider((ref) => DocumentRepository());
