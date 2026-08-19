/// Registering a Knowledge Base with the server and reading back who may see
/// it. The bundle itself stays on disk; this is only the shared record of it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/features/auth/data/auth_repository.dart';
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
