/// Registering a Knowledge Base with the server and reading back who may see
/// it. The bundle itself stays on disk; this is only the shared record of it.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

enum CollaborationRole { owner, coOwner, editor, reviewer }

extension CollaborationRoleValue on CollaborationRole {
  String get databaseValue => switch (this) {
    CollaborationRole.owner => 'owner',
    CollaborationRole.coOwner => 'co_owner',
    CollaborationRole.editor => 'editor',
    CollaborationRole.reviewer => 'reviewer',
  };

  String get label => switch (this) {
    CollaborationRole.owner => 'Owner',
    CollaborationRole.coOwner => 'Co-Owner',
    CollaborationRole.editor => 'Editor',
    CollaborationRole.reviewer => 'Reviewer',
  };

  static CollaborationRole fromDatabase(String value) => switch (value) {
    'owner' => CollaborationRole.owner,
    'co_owner' => CollaborationRole.coOwner,
    'reviewer' => CollaborationRole.reviewer,
    _ => CollaborationRole.editor,
  };
}

class KbCollaborator {
  const KbCollaborator({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.role,
    required this.accepted,
  });

  final String userId;
  final String username;
  final String displayName;
  final CollaborationRole role;
  final bool accepted;
}

class KbInvitation {
  const KbInvitation({
    required this.kbId,
    required this.name,
    required this.role,
  });
  final String kbId;
  final String name;
  final CollaborationRole role;
}

enum SyncHealth { inactive, checking, active, offline, unauthorized, error }

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
  Future<void> invite({
    required String kbId,
    required String username,
    required CollaborationRole role,
  }) async {
    try {
      await supabase.rpc(
        'invite_kb_member_by_username',
        params: {
          'p_kb_id': kbId,
          'p_username': normalizeUsername(username),
          'p_role': role.databaseValue,
        },
      );
    } on PostgrestException catch (error) {
      throw SyncException(error.message);
    }
  }

  Future<void> acceptInvitation(String kbId) =>
      supabase.rpc('accept_kb_invitation', params: {'p_kb_id': kbId});

  Future<void> setRole({
    required String kbId,
    required String userId,
    required CollaborationRole role,
  }) => supabase.rpc(
    'set_kb_member_role',
    params: {
      'p_kb_id': kbId,
      'p_user_id': userId,
      'p_role': role.databaseValue,
    },
  );

  Future<void> removeMember({required String kbId, required String userId}) =>
      supabase.rpc(
        'remove_kb_member',
        params: {'p_kb_id': kbId, 'p_user_id': userId},
      );

  Future<List<KbCollaborator>> collaborators(String kbId) async {
    final memberRows = await supabase
        .from('kb_members')
        .select('user_id, role, accepted_at')
        .eq('kb_id', kbId);
    final members = memberRows.cast<Map<String, Object?>>();
    if (members.isEmpty) return const [];

    final ids = members.map((row) => row['user_id'] as String).toList();
    final profileRows = await supabase
        .from('profiles')
        .select('id, username, display_name')
        .inFilter('id', ids);
    final profiles = <String, Map<String, Object?>>{
      for (final row in profileRows.cast<Map<String, Object?>>())
        row['id'] as String: row,
    };

    final result = [
      for (final member in members)
        KbCollaborator(
          userId: member['user_id'] as String,
          username:
              profiles[member['user_id']]?['username'] as String? ?? 'unknown',
          displayName:
              profiles[member['user_id']]?['display_name'] as String? ??
              'Unknown collaborator',
          role: CollaborationRoleValue.fromDatabase(member['role'] as String),
          accepted: member['accepted_at'] != null,
        ),
    ];
    result.sort((a, b) {
      final byRole = a.role.index.compareTo(b.role.index);
      return byRole != 0 ? byRole : a.displayName.compareTo(b.displayName);
    });
    return result;
  }

  Future<List<KbInvitation>> invitations() async {
    final user = supabase.auth.currentUser;
    if (user == null) return const [];
    final rows = await supabase
        .from('kb_members')
        .select('kb_id, role, knowledge_bases(name)')
        .eq('user_id', user.id)
        .isFilter('accepted_at', null);
    return [
      for (final row in rows.cast<Map<String, Object?>>())
        KbInvitation(
          kbId: row['kb_id'] as String,
          name:
              (row['knowledge_bases'] as Map<String, Object?>?)?['name']
                  as String? ??
              'Shared Knowledge Base',
          role: CollaborationRoleValue.fromDatabase(row['role'] as String),
        ),
    ];
  }

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

final kbCollaboratorsProvider =
    FutureProvider.family<List<KbCollaborator>, String>(
      (ref, kbId) => ref.read(kbRepositoryProvider).collaborators(kbId),
    );

final kbInvitationsProvider = FutureProvider<List<KbInvitation>>((ref) {
  ref.watch(currentUserProvider);
  if (!isSupabaseConfigured) return Future.value(const []);
  return ref.read(kbRepositoryProvider).invitations();
});

final kbSyncHealthProvider = FutureProvider.family<SyncHealth, String>((
  ref,
  kbId,
) async {
  if (!isSupabaseConfigured || supabase.auth.currentUser == null) {
    return SyncHealth.inactive;
  }
  try {
    final row = await supabase
        .from('kb_members')
        .select('accepted_at')
        .eq('kb_id', kbId)
        .eq('user_id', supabase.auth.currentUser!.id)
        .maybeSingle();
    if (row == null || row['accepted_at'] == null) return SyncHealth.inactive;
    return SyncHealth.active;
  } on AuthException {
    return SyncHealth.unauthorized;
  } on PostgrestException catch (error) {
    return error.code == '42501' ? SyncHealth.unauthorized : SyncHealth.offline;
  } on Object {
    return SyncHealth.offline;
  }
});
