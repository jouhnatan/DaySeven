/// Change sets: the proposals one collaborator sends another, and the record
/// of what was accepted.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';

abstract interface class ChangeSetDataSource {
  Future<ChangeSet> propose({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    String? relativePath,
    required BlockDocument content,
  });

  Future<ChangeSet> proposeCreate({
    required String kbId,
    required String relativePath,
    required BlockDocument content,
  });

  Future<ChangeSet> proposeDelete({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    required String relativePath,
  });

  Future<List<ChangeSet>> pendingForKb(String kbId);
  Future<ChangeSet?> byId(String changeSetId);
  Future<String?> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
    String? reviewNote,
  });
  Future<void> reject(String changeSetId, {String? reviewNote});
  Future<void> withdrawForDocument({
    required String kbId,
    required String documentId,
  });
}

class ChangeSetRepository implements ChangeSetDataSource {
  ChangeSetRepository({this.clientOverride});

  final SupabaseClient? clientOverride;
  SupabaseClient get client => clientOverride ?? supabase;

  static const _select =
      'id, kb_id, document_id, base_revision_id, content, author_id, status, '
      'resulting_revision_id, created_at, resolved_at, resolved_by, '
      'operation, target_document_id, proposed_path, updated_at, review_note';

  Future<List<ChangeSet>> _withAuthorProfiles(
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final authorIds = rows.map((row) => row['author_id'] as String).toSet();
    final profiles = await client
        .from('profiles')
        .select('id, username, display_name')
        .inFilter('id', authorIds.toList());
    final byId = <String, Map<String, Object?>>{
      for (final profile in profiles) profile['id'] as String: profile,
    };
    return rows.map((row) {
      final authorId = row['author_id'] as String;
      return ChangeSet.fromRow({
        ...row,
        'profiles': byId[authorId] ?? const <String, Object?>{},
      });
    }).toList();
  }

  /// Saves an edit as a proposal instead of writing it to the document.
  @override
  Future<ChangeSet> propose({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    String? relativePath,
    required BlockDocument content,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to propose a change.');

    final value = await client.rpc(
      'submit_change_set',
      params: {
        'p_kb_id': kbId,
        'p_document_id': documentId,
        'p_target_document_id': documentId,
        'p_base_revision_id': baseRevisionId,
        'p_operation': 'update',
        'p_proposed_path': relativePath,
        'p_content': content.toJson(),
      },
    );
    final raw = value is List ? value.single : value;
    final id = (raw as Map<String, Object?>)['id'] as String;
    return (await byId(id))!;
  }

  @override
  Future<ChangeSet> proposeCreate({
    required String kbId,
    required String relativePath,
    required BlockDocument content,
  }) => _submit(
    kbId: kbId,
    documentId: null,
    targetDocumentId: content.id,
    baseRevisionId: null,
    operation: ChangeSetOperation.create,
    relativePath: relativePath,
    content: content,
  );

  @override
  Future<ChangeSet> proposeDelete({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    required String relativePath,
  }) => _submit(
    kbId: kbId,
    documentId: documentId,
    targetDocumentId: documentId,
    baseRevisionId: baseRevisionId,
    operation: ChangeSetOperation.delete,
    relativePath: relativePath,
    content: null,
  );

  Future<ChangeSet> _submit({
    required String kbId,
    required String? documentId,
    required String targetDocumentId,
    required String? baseRevisionId,
    required ChangeSetOperation operation,
    required String? relativePath,
    required BlockDocument? content,
  }) async {
    final user = client.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to propose a change.');
    final value = await client.rpc(
      'submit_change_set',
      params: {
        'p_kb_id': kbId,
        'p_document_id': documentId,
        'p_target_document_id': targetDocumentId,
        'p_base_revision_id': baseRevisionId,
        'p_operation': operation.name,
        'p_proposed_path': relativePath,
        'p_content': content?.toJson(),
      },
    );
    final raw = value is List ? value.single : value;
    final id = (raw as Map<String, Object?>)['id'] as String;
    return (await byId(id))!;
  }

  @override
  Future<List<ChangeSet>> pendingForKb(String kbId) async {
    final rows = await client
        .from('change_sets')
        .select(_select)
        .eq('kb_id', kbId)
        .eq('status', 'pending')
        .order('updated_at', ascending: false);
    return _withAuthorProfiles(rows.cast<Map<String, Object?>>());
  }

  @override
  Future<ChangeSet?> byId(String changeSetId) async {
    final row = await client
        .from('change_sets')
        .select(_select)
        .eq('id', changeSetId)
        .maybeSingle();
    if (row == null) return null;
    return (await _withAuthorProfiles([row])).single;
  }

  /// Writes the merged document as a new revision and marks the proposal
  /// approved, in one transaction on the server.
  @override
  Future<String?> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
    String? reviewNote,
  }) async {
    final revisionId = await client.rpc(
      'approve_change_set',
      params: {
        'p_change_set_id': changeSetId,
        'p_merged_content': merged.toJson(),
        'p_content_hash': merged.contentHash,
        'p_expected_current_revision': expectedCurrentRevisionId,
        'p_review_note': reviewNote,
      },
    );
    return revisionId as String?;
  }

  /// Marks the proposal rejected. Nothing else changes: no revision is written
  /// and the document is untouched.
  @override
  Future<void> reject(String changeSetId, {String? reviewNote}) => client.rpc(
    'reject_change_set',
    params: {'p_change_set_id': changeSetId, 'p_review_note': reviewNote},
  );

  @override
  Future<void> withdrawForDocument({
    required String kbId,
    required String documentId,
  }) => client.rpc(
    'withdraw_pending_change_set',
    params: {'p_kb_id': kbId, 'p_target_document_id': documentId},
  );
}

final changeSetRepositoryProvider = Provider<ChangeSetDataSource>(
  (ref) => ChangeSetRepository(),
);
