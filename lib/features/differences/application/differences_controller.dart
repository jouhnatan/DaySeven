/// Durable pending-review state and explicit reviewed-edit submission.
///
/// Realtime only wakes this controller. Postgres is always queried before the
/// queue changes, so a missed WebSocket event cannot lose a proposal.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/features/differences/data/change_set_repository.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/retry_budget.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';

enum DifferencesLoadStatus { inactive, loading, ready, empty, offline, error }

enum DifferencesRealtimeHealth { inactive, connecting, connected, error }

enum DifferenceSyncPhase {
  savingLocally,
  savedLocally,
  publishing,
  proposing,
  syncingForReview,
  waitingForReview,
  published,
  synced,
  offline,
  conflict,
  error,
}

class DocumentReviewSyncState {
  const DocumentReviewSyncState(this.phase, {this.detail, this.proposalId});

  final DifferenceSyncPhase phase;
  final String? detail;
  final String? proposalId;

  String get label => switch (phase) {
    DifferenceSyncPhase.savingLocally => 'Saving locally',
    DifferenceSyncPhase.savedLocally => 'Saved locally',
    DifferenceSyncPhase.publishing => 'Publishing',
    DifferenceSyncPhase.proposing => 'Proposing',
    DifferenceSyncPhase.syncingForReview => 'Syncing for review',
    DifferenceSyncPhase.waitingForReview => 'Waiting for review',
    DifferenceSyncPhase.published => 'Published',
    DifferenceSyncPhase.synced => 'Synced',
    DifferenceSyncPhase.offline => 'Offline',
    DifferenceSyncPhase.conflict => 'Conflict',
    DifferenceSyncPhase.error => 'Error',
  };
}

class DifferencesState {
  const DifferencesState({
    this.proposals = const [],
    this.status = DifferencesLoadStatus.inactive,
    this.realtimeHealth = DifferencesRealtimeHealth.inactive,
    this.errorMessage,
    this.documentSync = const {},
    this.lastRefreshedAt,
  });

  final List<ChangeSet> proposals;
  final DifferencesLoadStatus status;
  final DifferencesRealtimeHealth realtimeHealth;
  final String? errorMessage;
  final Map<String, DocumentReviewSyncState> documentSync;
  final DateTime? lastRefreshedAt;

  int get pendingCount => proposals.length;
  bool get isRefreshing => status == DifferencesLoadStatus.loading;

  DifferencesState copyWith({
    List<ChangeSet>? proposals,
    DifferencesLoadStatus? status,
    DifferencesRealtimeHealth? realtimeHealth,
    String? Function()? errorMessage,
    Map<String, DocumentReviewSyncState>? documentSync,
    DateTime? lastRefreshedAt,
  }) => DifferencesState(
    proposals: proposals ?? this.proposals,
    status: status ?? this.status,
    realtimeHealth: realtimeHealth ?? this.realtimeHealth,
    errorMessage: errorMessage == null ? this.errorMessage : errorMessage(),
    documentSync: documentSync ?? this.documentSync,
    lastRefreshedAt: lastRefreshedAt ?? this.lastRefreshedAt,
  );
}

final differencesNetworkEnabledProvider = Provider<bool>(
  (ref) => isSupabaseConfigured,
);

final differencesRealtimeEnabledProvider = Provider<bool>(
  (ref) => ref.watch(differencesNetworkEnabledProvider),
);

/// A Realtime/focus wake-up signal. Consumers must still read canonical state
/// from Postgres before touching a local working copy.
final canonicalSyncWakeProvider = StateProvider<int>((ref) => 0);

final differencesControllerProvider =
    StateNotifierProvider<DifferencesController, DifferencesState>(
      DifferencesController.new,
    );

final differencesStateProvider = Provider<DifferencesState>(
  (ref) => ref.watch(differencesControllerProvider),
);

final differencesForOpenDocumentProvider = Provider<List<ChangeSet>>((ref) {
  final open = ref.watch(documentControllerProvider);
  if (open == null) return const [];
  return ref
      .watch(differencesStateProvider)
      .proposals
      .where((item) => item.targetDocumentId == open.document.id)
      .toList(growable: false);
});

final openDocumentReviewSyncProvider = Provider<DocumentReviewSyncState?>((
  ref,
) {
  final open = ref.watch(documentControllerProvider);
  if (open == null) return null;
  return ref.watch(differencesStateProvider).documentSync[open.document.id];
});

class DifferencesController extends StateNotifier<DifferencesState>
    with WidgetsBindingObserver {
  DifferencesController(this._ref) : super(const DifferencesState()) {
    WidgetsBinding.instance.addObserver(this);
    _ref.listen(kbSessionProvider, (_, _) => unawaited(_contextChanged()));
    _ref.listen(currentUserProvider, (_, _) => unawaited(_contextChanged()));
    _ref.listen<OpenDocument?>(documentControllerProvider, _documentChanged);
    unawaited(_contextChanged());
  }

  final Ref _ref;
  RealtimeChannel? _channel;
  final Map<String, OpenDocument> _pendingDocuments = {};
  final Map<String, Future<void>> _activeSubmissions = {};

  /// Stops a rejected submission from being resent on a loop. Cleared per
  /// document by a landed write or by the person editing again.
  final RetryBudget _submitBudget = RetryBudget();
  String? _boundKbId;
  String? _boundUserId;
  int _refreshGeneration = 0;

  List<ChangeSet> forDocument(String documentId) => state.proposals
      .where((proposal) => proposal.targetDocumentId == documentId)
      .toList(growable: false);

  Future<void> _contextChanged() async {
    await _bindRealtime();
    await refresh(showLoading: true);
  }

  Future<void> _bindRealtime() async {
    final session = _ref.read(kbSessionProvider);
    final user = _ref.read(currentUserProvider);
    final enabled = _ref.read(differencesRealtimeEnabledProvider);
    final kbId = session?.kb.manifest.kbId;
    final userId = user?.id;
    if (_boundKbId == kbId && _boundUserId == userId && _channel != null) {
      return;
    }

    final previous = _channel;
    _channel = null;
    _boundKbId = kbId;
    _boundUserId = userId;
    if (previous != null && enabled) {
      await supabase.removeChannel(previous);
    }

    if (kbId == null || user == null || !enabled) {
      state = state.copyWith(
        realtimeHealth: DifferencesRealtimeHealth.inactive,
      );
      return;
    }

    state = state.copyWith(
      realtimeHealth: DifferencesRealtimeHealth.connecting,
    );
    final channel = supabase.channel(
      'kb:$kbId',
      opts: const RealtimeChannelConfig(private: true),
    );
    _channel = channel;
    channel
        .onBroadcast(
          event: 'proposal_created',
          callback: (payload) {
            try {
              ProposalNotification.fromPayload(payload);
              unawaited(refresh(showLoading: false));
            } on Object {
              // Unknown payloads never replace the durable REST state.
            }
          },
        )
        .onBroadcast(
          event: 'document_published',
          callback: (_) {
            _ref.read(canonicalSyncWakeProvider.notifier).state++;
          },
        )
        .onBroadcast(
          event: 'document_protection_changed',
          callback: (_) {
            _ref.read(canonicalSyncWakeProvider.notifier).state++;
          },
        )
        .subscribe((status, error) {
          if (!mounted || !identical(_channel, channel)) return;
          state = state.copyWith(
            realtimeHealth: switch (status) {
              RealtimeSubscribeStatus.subscribed =>
                DifferencesRealtimeHealth.connected,
              RealtimeSubscribeStatus.channelError ||
              RealtimeSubscribeStatus.timedOut =>
                DifferencesRealtimeHealth.error,
              RealtimeSubscribeStatus.closed =>
                DifferencesRealtimeHealth.inactive,
            },
          );
        });
  }

  Future<void> refresh({bool showLoading = false}) async {
    final generation = ++_refreshGeneration;
    final session = _ref.read(kbSessionProvider);
    final user = _ref.read(currentUserProvider);
    if (session == null ||
        user == null ||
        !_ref.read(differencesNetworkEnabledProvider)) {
      if (!mounted || generation != _refreshGeneration) return;
      state = state.copyWith(
        proposals: const [],
        status: DifferencesLoadStatus.inactive,
        errorMessage: () => null,
      );
      return;
    }

    if (showLoading || state.proposals.isEmpty) {
      state = state.copyWith(
        status: DifferencesLoadStatus.loading,
        errorMessage: () => null,
      );
    }
    try {
      final pending = await _ref
          .read(changeSetRepositoryProvider)
          .pendingForKb(session.kb.manifest.kbId);
      if (!mounted || generation != _refreshGeneration) return;
      final reviewable = pending
          .where((proposal) => proposal.authorId != user.id)
          .toList(growable: false);
      state = state.copyWith(
        proposals: reviewable,
        status: reviewable.isEmpty
            ? DifferencesLoadStatus.empty
            : DifferencesLoadStatus.ready,
        errorMessage: () => null,
        lastRefreshedAt: DateTime.now(),
      );
    } on Object catch (error) {
      if (!mounted || generation != _refreshGeneration) return;
      state = state.copyWith(
        status: _isOffline(error)
            ? DifferencesLoadStatus.offline
            : DifferencesLoadStatus.error,
        errorMessage: () => describeError(error),
      );
    }
  }

  void _documentChanged(OpenDocument? previous, OpenDocument? next) {
    if (next == null) return;
    final pathChanged =
        previous != null &&
        previous.document.id == next.document.id &&
        previous.relativePath != next.relativePath;
    final changed =
        previous == null ||
        previous.document.id != next.document.id ||
        previous.document.contentHash != next.document.contentHash ||
        previous.relativePath != next.relativePath ||
        previous.dirty != next.dirty;
    if (!changed) return;
    final contentChanged =
        previous == null ||
        previous.document.id != next.document.id ||
        previous.document.contentHash != next.document.contentHash;
    // Only new content counts as new intent. A path or dirty-flag change can
    // come from the sync machinery itself, and must not hand a looping
    // submission a fresh budget.
    if (contentChanged) _submitBudget.reset(next.document.id);
    _setDocumentSync(
      next.document.id,
      DocumentReviewSyncState(
        next.dirty || pathChanged
            ? DifferenceSyncPhase.savingLocally
            : DifferenceSyncPhase.savedLocally,
      ),
    );
    _pendingDocuments[next.document.id] = next;
  }

  Future<void> _submitDebounced(String documentId) async {
    final active = _activeSubmissions[documentId];
    if (active != null) {
      await active;
      // A failed submission leaves its working copy queued so the edit is not
      // lost. That queued copy must not re-enter the drain immediately: doing
      // so turns one rejected proposal into an unbounded request loop, which is
      // how 5.57M doomed publishes reached the server on 2026-08-25. The budget
      // is what makes the retry deliberate rather than automatic.
      if (_pendingDocuments.containsKey(documentId) &&
          _submitBudget.allows(documentId)) {
        await _submitDebounced(documentId);
      }
      return;
    }
    if (!_submitBudget.allows(documentId)) return;

    final submission = _performSubmission(documentId);
    _activeSubmissions[documentId] = submission;
    try {
      await submission;
    } finally {
      if (identical(_activeSubmissions[documentId], submission)) {
        _activeSubmissions.remove(documentId);
      }
    }
  }

  Future<void> _performSubmission(String documentId) async {
    final scheduled = _pendingDocuments[documentId];
    if (scheduled == null) return;
    final role = await _ref.read(kbRoleProvider.future);
    if (role != KbRole.editor && role != KbRole.coOwner) {
      _pendingDocuments.remove(documentId);
      _setDocumentSync(
        documentId,
        const DocumentReviewSyncState(DifferenceSyncPhase.synced),
      );
      return;
    }

    final session = _ref.read(kbSessionProvider);
    if (session == null || !_ref.read(differencesNetworkEnabledProvider)) {
      _setDocumentSync(
        documentId,
        const DocumentReviewSyncState(
          DifferenceSyncPhase.offline,
          detail: 'The edit is safe on this device and will retry when online.',
        ),
      );
      return;
    }

    try {
      var workingCopy = scheduled;
      final open = _ref.read(documentControllerProvider);
      if (open != null && open.document.id == documentId) {
        await _ref.read(documentControllerProvider.notifier).flush();
        final flushed = _ref.read(documentControllerProvider);
        if (flushed != null && flushed.document.id == documentId) {
          workingCopy = flushed;
        }
      }
      _setDocumentSync(
        documentId,
        const DocumentReviewSyncState(DifferenceSyncPhase.syncingForReview),
      );

      final ledger = await SyncLedger.open(session.kb);
      final synced = ledger.document(documentId);
      if (synced != null &&
          synced.contentHash == workingCopy.document.contentHash &&
          synced.path == workingCopy.relativePath) {
        _removeSubmittedWorkingCopy(documentId, workingCopy);
        _submitBudget.recordSuccess(documentId);
        _setDocumentSync(
          documentId,
          const DocumentReviewSyncState(DifferenceSyncPhase.synced),
        );
        return;
      }

      await _ref
          .read(assetRepositoryProvider)
          .uploadReferenced(kb: session.kb, document: workingCopy.document);
      final repository = _ref.read(changeSetRepositoryProvider);
      final base =
          synced?.revisionId ??
          await _ref
              .read(documentRepositoryProvider)
              .currentRevisionId(documentId);
      final proposal = base == null
          ? await repository.proposeCreate(
              kbId: session.kb.manifest.kbId,
              relativePath: workingCopy.relativePath,
              content: workingCopy.document,
            )
          : await repository.propose(
              kbId: session.kb.manifest.kbId,
              documentId: documentId,
              baseRevisionId: base,
              relativePath:
                  synced == null || synced.path != workingCopy.relativePath
                  ? workingCopy.relativePath
                  : null,
              content: workingCopy.document,
            );
      _removeSubmittedWorkingCopy(documentId, workingCopy);
      _submitBudget.recordSuccess(documentId);
      _setDocumentSync(
        documentId,
        DocumentReviewSyncState(
          DifferenceSyncPhase.waitingForReview,
          proposalId: proposal.id,
        ),
      );
      await refresh(showLoading: false);
    } on Object catch (error) {
      _submitBudget.recordFailure(documentId);
      final exhausted = _submitBudget.isExhausted(documentId);
      _setDocumentSync(
        documentId,
        DocumentReviewSyncState(
          _isConflict(error)
              ? DifferenceSyncPhase.conflict
              : _isOffline(error)
              ? DifferenceSyncPhase.offline
              : DifferenceSyncPhase.error,
          detail: exhausted
              // The edit is still queued and still safe on disk; what has
              // stopped is the automatic resending of it.
              ? '${describeError(error)}\n\nThis edit stopped retrying after '
                    '${_submitBudget.maxConsecutiveFailures} attempts. It is '
                    'safe on this device. Sync the Knowledge Base, or edit the '
                    'document again, to try once more.'
              : describeError(error),
        ),
      );
    }
  }

  /// The explicit "send this now" path. A person asking again is fresh intent,
  /// so it clears the budget rather than being held off by it — the budget
  /// exists to stop the *automatic* drain from resending on a loop, not to make
  /// someone wait after they have decided to retry.
  Future<void> submitPendingEditNow(String documentId) async {
    final open = _ref.read(documentControllerProvider);
    if (open != null && open.document.id == documentId) {
      _pendingDocuments[documentId] = open;
    }
    _submitBudget.reset(documentId);
    await _submitDebounced(documentId);
  }

  /// Compatibility hook for explicit direct publishing on older UI paths.
  Future<void> prepareDirectPublish(String documentId) async {
    _pendingDocuments.remove(documentId);
    final active = _activeSubmissions[documentId];
    if (active != null) await active;
    final session = _ref.read(kbSessionProvider);
    if (session == null || !_ref.read(differencesNetworkEnabledProvider)) {
      return;
    }
    await _ref
        .read(changeSetRepositoryProvider)
        .withdrawForDocument(
          kbId: session.kb.manifest.kbId,
          documentId: documentId,
        );
  }

  void markDirectPublished(String documentId) {
    _setDocumentSync(
      documentId,
      const DocumentReviewSyncState(DifferenceSyncPhase.synced),
    );
    unawaited(refresh(showLoading: false));
  }

  void markPublishing(String documentId, {required bool willPropose}) {
    _setDocumentSync(
      documentId,
      DocumentReviewSyncState(
        willPropose
            ? DifferenceSyncPhase.proposing
            : DifferenceSyncPhase.publishing,
      ),
    );
  }

  void markPublished(String documentId) {
    _pendingDocuments.remove(documentId);
    _setDocumentSync(
      documentId,
      const DocumentReviewSyncState(DifferenceSyncPhase.published),
    );
    unawaited(refresh(showLoading: false));
  }

  void markProposed(String documentId, String proposalId) {
    _pendingDocuments.remove(documentId);
    _setDocumentSync(
      documentId,
      DocumentReviewSyncState(
        DifferenceSyncPhase.waitingForReview,
        proposalId: proposalId,
      ),
    );
    unawaited(refresh(showLoading: false));
  }

  void markConflict(String documentId, String detail) {
    _setDocumentSync(
      documentId,
      DocumentReviewSyncState(DifferenceSyncPhase.conflict, detail: detail),
    );
  }

  void markPublishError(String documentId, Object error) {
    _setDocumentSync(
      documentId,
      DocumentReviewSyncState(
        _isOffline(error)
            ? DifferenceSyncPhase.offline
            : DifferenceSyncPhase.error,
        detail: describeError(error),
      ),
    );
  }

  void remove(String changeSetId) {
    state = state.copyWith(
      proposals: state.proposals
          .where((proposal) => proposal.id != changeSetId)
          .toList(growable: false),
    );
  }

  void _setDocumentSync(String documentId, DocumentReviewSyncState next) {
    if (!mounted) return;
    state = state.copyWith(
      documentSync: {...state.documentSync, documentId: next},
    );
  }

  void _removeSubmittedWorkingCopy(String documentId, OpenDocument submitted) {
    final pending = _pendingDocuments[documentId];
    if (pending != null &&
        pending.document.contentHash == submitted.document.contentHash &&
        pending.relativePath == submitted.relativePath) {
      _pendingDocuments.remove(documentId);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(refresh(showLoading: false));
      _ref.read(canonicalSyncWakeProvider.notifier).state++;
    }
  }

  bool _isConflict(Object error) =>
      error is PostgrestException && error.code == '40001';

  bool _isOffline(Object error) =>
      error is SocketException || error is TimeoutException;

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    final channel = _channel;
    if (channel != null && _ref.read(differencesRealtimeEnabledProvider)) {
      unawaited(supabase.removeChannel(channel));
    }
    super.dispose();
  }
}
