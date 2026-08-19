/// The repositories that move Knowledge Bases, documents, revisions and change
/// sets between the local folder and Postgres.
///
/// The client itself and the error vocabulary live in
/// `lib/shared/backend/supabase_client.dart`; signing in lives in `lib/auth/`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/domain/revision.dart';

// ------------------------------------------------------------ knowledge base --

class KbRepository {
  /// Registers a locally created Knowledge Base with the server and makes the
  /// creator its owner. The folder path is never sent: each member chooses
  /// their own location.
  Future<void> createRemote({
    required String kbId,
    required String name,
  }) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase.from('knowledge_bases').insert({
      'id': kbId,
      'name': name,
      'owner_id': user.id,
    });
    await supabase.from('kb_members').insert({
      'kb_id': kbId,
      'user_id': user.id,
      'role': 'owner',
      'accepted_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Invites a collaborator by username. Resolving it to an account happens
  /// server-side, behind an owner check.
  Future<void> invite({required String kbId, required String username}) async {
    try {
      await supabase.rpc(
        'invite_kb_member_by_username',
        params: {'p_kb_id': kbId, 'p_username': normalizeUsername(username)},
      );
    } on PostgrestException catch (error) {
      throw SyncException(error.message);
    }
  }

  Future<void> acceptInvitation(String kbId) =>
      supabase.rpc('accept_kb_invitation', params: {'p_kb_id': kbId});

  /// Knowledge Bases this account belongs to, including unaccepted invitations.
  Future<List<Map<String, Object?>>> myMemberships() async {
    final rows = await supabase
        .from('kb_members')
        .select('kb_id, role, accepted_at, knowledge_bases(name)');
    return rows.cast<Map<String, Object?>>();
  }
}

final kbRepositoryProvider = Provider((ref) => KbRepository());

// ------------------------------------------------------ documents & revisions --

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
        .update({'current_revision_id': revisionId, 'title': document.title})
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
        .eq('kb_id', kbId);
    return rows.cast<Map<String, Object?>>();
  }
}

final documentRepositoryProvider = Provider((ref) => DocumentRepository());

// ------------------------------------------------------------- change sets --

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
