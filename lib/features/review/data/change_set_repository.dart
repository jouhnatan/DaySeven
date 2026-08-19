/// Change sets: the proposals one collaborator sends another, and the record
/// of what was accepted.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/domain/revision.dart';

class ChangeSetRepository {
  static const _select =
      'id, kb_id, document_id, base_revision_id, content, author_id, status, '
      'resulting_revision_id, created_at, resolved_at, resolved_by, '
      'profiles!change_sets_author_id_fkey(display_name)';

  /// Saves an edit as a proposal instead of writing it to the document.
  Future<ChangeSet> propose({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    required BlockDocument content,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) throw const SyncException('Sign in to propose a change.');

    final row = await supabase
        .from('change_sets')
        .insert({
          'kb_id': kbId,
          'document_id': documentId,
          'base_revision_id': baseRevisionId,
          'content': content.toJson(),
          'author_id': user.id,
          'status': 'pending',
        })
        .select(_select)
        .single();
    return ChangeSet.fromRow(row);
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
  Future<String> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
  }) async {
    final revisionId = await supabase.rpc(
      'approve_change_set',
      params: {
        'p_change_set_id': changeSetId,
        'p_merged_content': merged.toJson(),
        'p_content_hash': merged.contentHash,
        'p_expected_current_revision': expectedCurrentRevisionId,
      },
    );
    return revisionId as String;
  }

  /// Marks the proposal rejected. Nothing else changes: no revision is written
  /// and the document is untouched.
  Future<void> reject(String changeSetId) => supabase.rpc(
    'reject_change_set',
    params: {'p_change_set_id': changeSetId},
  );
}

final changeSetRepositoryProvider = Provider((ref) => ChangeSetRepository());
