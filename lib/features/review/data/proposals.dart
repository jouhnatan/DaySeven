/// Proposal awareness.
///
/// Realtime is used only to say that a proposal exists: the payload carries
/// identifiers and the author's display name, nothing else. The content is
/// fetched over the normal data path when the reviewer opens the diff.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/blocks/revision.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/features/review/data/change_set_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

/// Subscribes to the open Knowledge Base's private channel. Emits each time a
/// proposal is announced, which is the cue to re-check the open document.
final proposalNoticeProvider = StreamProvider<ProposalNotification>((ref) {
  final session = ref.watch(kbSessionProvider);
  final user = ref.watch(currentUserProvider);
  if (session == null || user == null || !isSupabaseConfigured) {
    return const Stream.empty();
  }

  final controller = StreamController<ProposalNotification>();
  final channel = supabase.channel(
    'kb:${session.kb.manifest.kbId}',
    opts: const RealtimeChannelConfig(private: true),
  );

  channel
      .onBroadcast(
        event: 'proposal_created',
        callback: (payload) {
          try {
            controller.add(ProposalNotification.fromPayload(payload));
          } on TypeError {
            // A payload we do not recognise is not worth interrupting the user for.
          }
        },
      )
      .subscribe();

  ref.onDispose(() {
    controller.close();
    supabase.removeChannel(channel);
  });

  return controller.stream;
});

/// Every proposal awaiting review in the open Knowledge Base.
final pendingProposalsProvider =
    StateNotifierProvider<PendingProposalsController, List<ChangeSet>>((ref) {
      final controller = PendingProposalsController(ref);
      ref.listen(proposalNoticeProvider, (_, next) {
        if (next.valueOrNull != null) controller.refresh();
      });
      ref.listen(kbSessionProvider, (_, _) => controller.refresh());
      controller.refresh();
      return controller;
    });

/// Compatibility/current-document projection used by the toolbar dot.
final pendingProposalProvider = Provider<ChangeSet?>((ref) {
  final open = ref.watch(documentControllerProvider);
  final user = ref.watch(currentUserProvider);
  final proposals = ref.watch(pendingProposalsProvider);
  if (open == null || user == null) return null;
  for (final proposal in proposals) {
    if (proposal.targetDocumentId == open.document.id &&
        proposal.authorId != user.id) {
      return proposal;
    }
  }
  return null;
});

class PendingProposalsController extends StateNotifier<List<ChangeSet>> {
  PendingProposalsController(this._ref) : super(const []);

  final Ref _ref;

  Future<void> refresh() async {
    final session = _ref.read(kbSessionProvider);
    final user = _ref.read(currentUserProvider);
    if (session == null || user == null || !isSupabaseConfigured) {
      if (mounted) state = const [];
      return;
    }

    try {
      final pending = await _ref
          .read(changeSetRepositoryProvider)
          .pendingForKb(session.kb.manifest.kbId);
      if (mounted) state = pending.where((p) => p.authorId != user.id).toList();
    } on PostgrestException {
      if (mounted) state = const [];
    }
  }

  void remove(String changeSetId) {
    if (mounted) state = state.where((p) => p.id != changeSetId).toList();
  }
}
