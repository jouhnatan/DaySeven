/// Supabase wiring: the client, and the repositories that move Knowledge Bases,
/// documents, revisions and change sets between the local folder and Postgres.
///
/// Signing in lives in `lib/auth/` — this file only needs the client.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/auth/auth_repository.dart';

import 'package:dayseven/domain/blocks.dart';
import 'package:dayseven/domain/revision.dart';

/// Supplied at build time with `--dart-define-from-file=env/supabase.json`.
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

/// True when the app was built with Supabase credentials. Without them the
/// application still runs entirely locally — a Knowledge Base is a folder, and
/// only collaboration needs the network.
bool get isSupabaseConfigured =>
    kSupabaseUrl.isNotEmpty && kSupabasePublishableKey.isNotEmpty;

Future<void> initSupabase() async {
  if (!isSupabaseConfigured) return;
  await Supabase.initialize(
    url: kSupabaseUrl,
    publishableKey: kSupabasePublishableKey,
  );
}

SupabaseClient get supabase => Supabase.instance.client;

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

/// Renders an error as something worth pasting: the message plus whatever
/// codes the failure carries, rather than just a class name.
String describeError(Object error) {
  if (error is AuthException) {
    final parts = <String>[
      error.message,
      if (error.statusCode != null) 'status ${error.statusCode}',
      if (error.code != null) 'code ${error.code}',
    ];
    final detail = 'Auth: ${parts.join(' · ')}';

    // Two failures here are project settings rather than anything the person
    // typed, and say so in terms of an email they never entered.
    final explanation = switch (error.code) {
      'email_not_confirmed' || 'over_email_send_rate_limit' =>
        'DaySeven accounts are username-only, but this project still has email '
            'confirmation switched on, so signing up tries to send mail. Turn '
            'off Authentication → Sign In / Providers → Email → "Confirm '
            'email" in the Supabase dashboard.',
      _ => null,
    };

    return explanation == null ? detail : '$explanation\n\n$detail';
  }

  if (error is PostgrestException) {
    final parts = <String>[
      error.message,
      if (error.code != null) 'code ${error.code}',
      if (error.details != null) 'details ${error.details}',
      if (error.hint != null) 'hint ${error.hint}',
    ];
    return 'Database: ${parts.join(' · ')}';
  }

  if (error is StorageException) {
    return 'Storage: ${error.message}'
        '${error.statusCode == null ? '' : ' · status ${error.statusCode}'}';
  }

  if (error is SyncException) return error.message;

  return '$error';
}

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
