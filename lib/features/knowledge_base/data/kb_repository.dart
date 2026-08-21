/// Registering a Knowledge Base with the server and reading back who may see
/// it. The bundle itself stays on disk; this is only the shared record of it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

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
    await supabase.rpc(
      'share_knowledge_base',
      params: {'p_kb_id': kbId, 'p_name': name},
    );
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

  /// Deletes the server-side mirror only. The Knowledge Base folder lives on
  /// the caller's disk and is never addressed by this operation.
  ///
  /// The RPC is owner-checked and deliberately treats an already-missing row
  /// as success, which makes disconnect safe to retry after an interrupted
  /// share or delete.
  Future<void> deleteRemote(String kbId) async {
    await supabase.rpc(
      'delete_shared_knowledge_base',
      params: {'p_kb_id': kbId},
    );
  }

  /// Knowledge Bases this account belongs to, including unaccepted invitations.
  Future<List<Map<String, Object?>>> myMemberships() async {
    final rows = await supabase
        .from('kb_members')
        .select('kb_id, role, accepted_at, knowledge_bases(name)');
    return rows.cast<Map<String, Object?>>();
  }
}

final kbRepositoryProvider = Provider((ref) => KbRepository());
