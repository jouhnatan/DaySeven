/// Change sets: the proposals one collaborator sends another, and the record
/// of what was accepted.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/revision.dart';

class ChangeSetRepository {
  static const _select =
      'id, kb_id, document_id, base_revision_id, content, author_id, status, '
      'resulting_revision_id, created_at, resolved_at, resolved_by, '
      'operation, target_document_id, proposed_path, updated_at, review_note, '
      'profiles!change_sets_author_id_fkey(display_name)';

  /// Saves an edit as a proposal instead of writing it to the document.
  Future<ChangeSet> propose({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    String? relativePath,
    required BlockDocument content,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to propose a change.');

    final value = await supabase.rpc(
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
    final user = supabase.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to propose a change.');
    final value = await supabase.rpc(
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

  /// The proposal waiting on a document, if there is one.
  Future<ChangeSet?> pendingFor(String documentId) async {
    final row = await supabase
        .from('change_sets')
        .select(_select)
        .eq('document_id', documentId)
        .eq('status', 'pending')
        .maybeSingle();
    return row == null ? null : ChangeSet.fromRow(row);
  }

  Future<List<ChangeSet>> pendingForKb(String kbId) async {
    final rows = await supabase
        .from('change_sets')
        .select(_select)
        .eq('kb_id', kbId)
        .eq('status', 'pending')
        .order('updated_at', ascending: false);
    return rows.cast<Map<String, Object?>>().map(ChangeSet.fromRow).toList();
  }

  Future<ChangeSet?> byId(String changeSetId) async {
    final row = await supabase
        .from('change_sets')
        .select(_select)
        .eq('id', changeSetId)
        .maybeSingle();
    return row == null ? null : ChangeSet.fromRow(row);
  }

  /// Writes the merged document as a new revision and marks the proposal
  /// approved, in one transaction on the server.
  Future<String?> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
    String? reviewNote,
  }) async {
    final revisionId = await supabase.rpc(
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
  Future<void> reject(String changeSetId, {String? reviewNote}) => supabase.rpc(
    'reject_change_set',
    params: {'p_change_set_id': changeSetId, 'p_review_note': reviewNote},
  );
}

final changeSetRepositoryProvider = Provider((ref) => ChangeSetRepository());
