/// Proposal awareness.
///
/// Realtime is used only to say that a proposal exists: the payload carries
/// identifiers and the author's display name, nothing else. The content is
/// fetched over the normal data path when the reviewer opens the diff.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../app/state.dart';
import '../domain/revision.dart';
import '../auth/auth_repository.dart';
import 'supabase.dart';

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

/// The proposal waiting on the document currently open, or null. This is what
/// lights the dot on the Differences button and what the diff view reviews.
final pendingProposalProvider =
    StateNotifierProvider<PendingProposalController, ChangeSet?>((ref) {
      final controller = PendingProposalController(ref);

      ref.listen<OpenDocument?>(documentControllerProvider, (_, open) {
        controller.refresh();
      });

      // A notice for the open document means re-checking; a notice for another
      // document is not this view's concern.
      ref.listen(proposalNoticeProvider, (_, next) {
        final notice = next.valueOrNull;
        final open = ref.read(documentControllerProvider);
        if (notice == null || open == null) return;
        if (notice.documentId == open.document.id) controller.refresh();
      });

      controller.refresh();
      return controller;
    });

class PendingProposalController extends StateNotifier<ChangeSet?> {
  PendingProposalController(this._ref) : super(null);

  final Ref _ref;

  Future<void> refresh() async {
    final open = _ref.read(documentControllerProvider);
    final user = _ref.read(currentUserProvider);
    if (open == null || user == null || !isSupabaseConfigured) {
      if (mounted) state = null;
      return;
    }

    try {
      final pending = await _ref
          .read(changeSetRepositoryProvider)
          .pendingFor(open.document.id);
      // Your own proposal is not yours to review.
      if (mounted) {
        state = pending?.authorId == user.id ? null : pending;
      }
    } on PostgrestException {
      if (mounted) state = null;
    }
  }

  /// Called after Approve or Reject, both of which end the proposal.
  void clear() {
    if (mounted) state = null;
  }
}
