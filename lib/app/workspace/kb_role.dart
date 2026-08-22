/// The signed-in account's role in the open Knowledge Base.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

enum KbRole { local, owner, coOwner, editor, reviewer, invited }

extension KbRolePublishing on KbRole {
  int? get publishingRank => switch (this) {
    KbRole.editor => MinimumPublishRole.editor.rank,
    KbRole.coOwner => MinimumPublishRole.coOwner.rank,
    KbRole.owner => MinimumPublishRole.owner.rank,
    KbRole.local || KbRole.reviewer || KbRole.invited => null,
  };

  MinimumPublishRole? get minimumPublishRole => switch (this) {
    KbRole.editor => MinimumPublishRole.editor,
    KbRole.coOwner => MinimumPublishRole.coOwner,
    KbRole.owner => MinimumPublishRole.owner,
    KbRole.local || KbRole.reviewer || KbRole.invited => null,
  };

  bool meets(MinimumPublishRole minimumRole) =>
      publishingRank != null && publishingRank! >= minimumRole.rank;
}

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
