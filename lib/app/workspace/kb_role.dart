/// The signed-in account's role in the open Knowledge Base.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

enum KbRole { local, owner, coOwner, editor, reviewer, invited }

final kbRoleProvider = FutureProvider<KbRole>((ref) async {
  final session = ref.watch(kbSessionProvider);
  final user = ref.watch(currentUserProvider);
  if (session == null || user == null || !isSupabaseConfigured) {
    return KbRole.local;
  }

  try {
    final row = await supabase
        .from('kb_members')
        .select('role, accepted_at')
        .eq('kb_id', session.kb.manifest.kbId)
        .eq('user_id', user.id)
        .maybeSingle();
    if (row == null) return KbRole.local;
    if (row['accepted_at'] == null) return KbRole.invited;
    return switch (row['role']) {
      'owner' => KbRole.owner,
      'co_owner' => KbRole.coOwner,
      'reviewer' => KbRole.reviewer,
      _ => KbRole.editor,
    };
  } on PostgrestException {
    return KbRole.local;
  }
});
