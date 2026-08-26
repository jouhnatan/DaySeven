/// Drives one Knowledge Base's CRDT collaboration for as long as it is open.
///
/// Ties together four things that each know nothing about the others: the
/// local [WorkspaceStore] (a yrs document behind the Rust bridge), the durable
/// log in Postgres, the `crdt:<kbId>` Realtime topic, and the authorization
/// gate. The loop is:
///
///   join   -> pull everything since the remembered cursor, apply it
///   local  -> diff since the last send; broadcast it and persist it, or route
///             it into a proposal when the file is protected
///   remote -> queue it, stage it, judge it, and only then apply it
///
/// **Why both routes out.** Broadcast is immediate and keeps no history; the
/// log is durable and debounced to seconds. A peer that was offline sees none
/// of the broadcast and all of the log. Yjs updates are idempotent and
/// commutative, so receiving one twice costs nothing — the property that lets
/// these run at different rates without coordination.
///
/// **Why everything inbound is queued.** Applying an update crosses the FFI
/// bridge and mutates a document. Doing that concurrently for a burst of
/// arrivals is both a correctness problem and an unbounded amount of work
/// started at once, so arrivals go into a bounded queue drained one at a time.
/// When the queue is full the oldest is dropped, because the durable log makes
/// anything dropped recoverable and an unbounded queue does not.
///
/// What this deliberately does not do: it does not touch documents, revisions,
/// change_sets, or anything else the existing Supabase sync owns. Until CRDT
/// sync is proven end to end, that path stays authoritative and this one runs
/// beside it.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/retry_budget.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/security/security_log.dart';

/// How many inbound messages to hold while the applier works through them.
const int kMaxInboundQueue = 64;

enum CrdtLinkHealth {
  /// Not started, or stopped because collaboration is unavailable.
  inactive,

  /// Joining the topic or catching up from the log.
  connecting,

  /// Live: broadcasts flowing, log reachable.
  connected,

  /// The document is intact locally and edits are still being saved to disk;
  /// only the sharing of them has stopped.
  degraded,
}

/// Everything the UI needs to say what collaboration is doing.
class CrdtLinkState {
  const CrdtLinkState({
    this.health = CrdtLinkHealth.inactive,
    this.cursor = 0,
    this.pendingLocalPush = false,
    this.queuedInbound = 0,
    this.detail,
  });

  final CrdtLinkHealth health;

  /// Position in `yjs_updates` this peer has applied everything up to.
  final int cursor;

  /// Local edits made but not yet written to the durable log.
  final bool pendingLocalPush;

  /// Inbound messages waiting to be applied. A number that stays high means
  /// this device cannot keep up with the room.
  final int queuedInbound;

  final String? detail;

  CrdtLinkState copyWith({
    CrdtLinkHealth? health,
    int? cursor,
    bool? pendingLocalPush,
    int? queuedInbound,
    String? Function()? detail,
  }) => CrdtLinkState(
    health: health ?? this.health,
    cursor: cursor ?? this.cursor,
    pendingLocalPush: pendingLocalPush ?? this.pendingLocalPush,
    queuedInbound: queuedInbound ?? this.queuedInbound,
    detail: detail == null ? this.detail : detail(),
  );
}

class CrdtSession {
  CrdtSession({
    required this.kbId,
    required this.store,
    required this.repository,
    required this.authorId,
    required this.gate,
    SecurityLog? securityLog,
    RealtimeChannel? Function(String topic)? channelFactory,
    this.pushDebounce = kCrdtPushDebounce,
    this.broadcastDebounce = kCrdtBroadcastDebounce,
    this.maxInboundQueue = kMaxInboundQueue,
  }) : _channelFactory = channelFactory ?? _defaultChannel,
       securityLog =
           securityLog ?? SecurityLog(sink: const NullSecuritySink());

  final String kbId;
  final WorkspaceStore store;
  final CrdtSyncRepository repository;

  /// This device's authenticated user id. Used to skip our own broadcasts and
  /// to decide, before sending, whether an edit must become a proposal.
  final String authorId;

  /// Decides what inbound updates are allowed to do. Never null: a Knowledge
  /// Base with no policy still gets a gate, it simply has nothing protected.
  final CrdtAuthorizationGate gate;

  final SecurityLog securityLog;
  /// Returns null when there is no live channel to join — Supabase not
  /// configured, or a caller that wants durability without liveness. The
  /// session still works: it catches up from the log and pushes to it, and
  /// only the immediate half is missing.
  final RealtimeChannel? Function(String topic) _channelFactory;

  /// How long local edits accumulate before reaching the durable log.
  final Duration pushDebounce;

  /// How long they accumulate before reaching other people's screens.
  final Duration broadcastDebounce;

  final int maxInboundQueue;

  /// Pushing is automatic, so it needs the same protection as publishing: a
  /// rejected write must not be resent on a loop. One key, since the whole
  /// workspace pushes as a unit.
  final RetryBudget _pushBudget = RetryBudget();

  final CrdtAssembler _assembler = CrdtAssembler();
  final Queue<CrdtMessage> _inbound = Queue<CrdtMessage>();
  final math.Random _ids = math.Random();

  final _states = StreamController<CrdtLinkState>.broadcast();
  Stream<CrdtLinkState> get states => _states.stream;
  CrdtLinkState get state => _state;
  CrdtLinkState _state = const CrdtLinkState();

  /// File ids changed by updates that came from somewhere else. The caller
  /// materialises these to Markdown; this class never touches the filesystem.
  final _remoteChanges = StreamController<List<String>>.broadcast();
  Stream<List<String>> get remoteChanges => _remoteChanges.stream;

  /// Fires when a peer's update was refused. The UI can say so; the security
  /// log has already recorded it.
  final _refusals = StreamController<CrdtDecision>.broadcast();
  Stream<CrdtDecision> get refusals => _refusals.stream;

  RealtimeChannel? _channel;
  Timer? _pushTimer;
  Timer? _broadcastTimer;
  Uint8List? _lastSentStateVector;
  bool _started = false;
  bool _disposed = false;
  bool _draining = false;
  Future<void>? _activePush;

  static RealtimeChannel? _defaultChannel(String topic) =>
      supabase.channel(topic, opts: const RealtimeChannelConfig(private: true));

  String _newMessageId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '-${_ids.nextInt(1 << 32).toRadixString(36)}';

  // ------------------------------------------------------------- lifecycle --

  /// Catches up from the durable log, then joins the live topic.
  ///
  /// Catch-up comes first deliberately: joining first would let a broadcast
  /// land on a document that has not yet applied the history that broadcast
  /// assumes, and while Yjs tolerates that, it makes the cursor meaningless.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _emit(
      _state.copyWith(health: CrdtLinkHealth.connecting, detail: () => null),
    );

    try {
      await _catchUp();
    } on Object catch (error) {
      // A failed catch-up is not a failed session. The local document is whole
      // and still saving to disk; only sharing has stalled.
      _emit(
        _state.copyWith(
          health: CrdtLinkHealth.degraded,
          detail: () => describeError(error),
        ),
      );
    }

    _join();
  }

  /// Applies everything appended since [CrdtLinkState.cursor].
  ///
  /// The log is not gated. Everything in it was accepted by the server against
  /// its own rules, and a peer cannot write there without passing them —
  /// unlike a broadcast, which RLS admits on membership alone.
  Future<void> _catchUp() async {
    final catchUp = await repository.pull(
      kbId: kbId,
      since: _state.cursor == 0 ? null : _state.cursor,
    );
    final changed = <String>{};
    if (catchUp.snapshot != null) {
      changed.addAll(await store.applyUpdate(catchUp.snapshot!));
    }
    for (final update in catchUp.updates) {
      // Our own updates come back from the log too. Applying them is a no-op
      // to yrs, so they are not filtered out — doing so would risk dropping an
      // update that only looks like ours.
      changed.addAll(await store.applyUpdate(update.bytes));
    }
    _emit(_state.copyWith(cursor: catchUp.cursor));
    if (changed.isNotEmpty) _remoteChanges.add(changed.toList());
  }

  void _join() {
    if (_disposed) return;
    final topic = crdtTopicFor(kbId);
    final channel = _channelFactory(topic);
    if (channel == null) {
      // Durable sync without liveness. Edits still reach the log and still
      // arrive from it; they simply do not arrive the instant they are typed.
      _emit(
        _state.copyWith(
          health: CrdtLinkHealth.degraded,
          detail: () => 'Live collaboration is unavailable; edits still sync.',
        ),
      );
      return;
    }
    _channel = channel;
    channel
        .onBroadcast(
          event: kCrdtBroadcastEvent,
          callback: _receive,
        )
        .subscribe((status, error) {
          if (_disposed || !identical(_channel, channel)) return;
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
              securityLog.record(
                SecurityEventKind.channelJoined,
                facts: {'topic': topic, 'user_id': authorId},
              );
              _emit(
                _state.copyWith(
                  health: CrdtLinkHealth.connected,
                  detail: () => null,
                ),
              );
              // A resubscribe means we may have missed broadcasts while away.
              // The log is the only thing that can tell us what.
              unawaited(_catchUpQuietly());
            case RealtimeSubscribeStatus.channelError:
            case RealtimeSubscribeStatus.timedOut:
              securityLog.record(
                SecurityEventKind.channelError,
                facts: {'topic': topic, 'status': status.name},
              );
              _emit(
                _state.copyWith(
                  health: CrdtLinkHealth.degraded,
                  detail: () => error == null
                      ? 'Live collaboration dropped.'
                      : describeError(error),
                ),
              );
            case RealtimeSubscribeStatus.closed:
              securityLog.record(
                SecurityEventKind.channelLeft,
                facts: {'topic': topic, 'user_id': authorId},
              );
              _emit(_state.copyWith(health: CrdtLinkHealth.inactive));
          }
        });
  }

  Future<void> _catchUpQuietly() async {
    try {
      await _catchUp();
    } on Object {
      // Already reflected in health; a resubscribe is not worth an error toast.
    }
  }

  // ---------------------------------------------------------------- inbound --

  /// Feeds one raw broadcast frame in, as the channel would.
  ///
  /// Exposed for tests: the inbound half is where the interesting behaviour
  /// is, and a fake Realtime channel would test the mock rather than this.
  @visibleForTesting
  void receiveForTest(Map<String, dynamic> payload) => _receive(payload);

  /// Decodes one broadcast frame and queues whatever it completes.
  ///
  /// Synchronous on purpose: it must not await before enqueuing, or a burst
  /// interleaves and the queue bound stops meaning anything.
  void _receive(Map<String, dynamic> payload) {
    if (_disposed) return;
    final result = _assembler.accept(payload);

    if (result.isRejected) {
      securityLog.record(
        SecurityEventKind.protocolError,
        facts: {
          'topic': crdtTopicFor(kbId),
          'reason': result.rejection!.name,
          'sender_id': result.senderId,
        },
      );
      return;
    }
    if (result.isIncomplete) return;

    final message = result.message!;
    if (message.senderId == authorId) return;

    switch (message.type) {
      case CrdtMessageType.crdtUpdate:
      case CrdtMessageType.syncStep2:
        _enqueue(message);
      case CrdtMessageType.syncStep1:
        // A peer asking what it is missing. The durable log answers that far
        // better than we can, so this is acknowledged and ignored rather than
        // answered — replying would mean sending our whole state to anyone who
        // asks, repeatedly.
        break;
      case CrdtMessageType.proposalUpdate:
        // Proposals are durable and reviewed through the queue; the broadcast
        // is only a nudge that one arrived.
        _remoteChanges.add(const []);
      case CrdtMessageType.awareness:
      case CrdtMessageType.ping:
      case CrdtMessageType.pong:
        // Presence rides its own topic. These are accepted by the protocol so
        // that a peer sending them is not logged as an error, and otherwise
        // do nothing here.
        break;
    }
  }

  void _enqueue(CrdtMessage message) {
    _inbound.addLast(message);
    while (_inbound.length > maxInboundQueue) {
      final dropped = _inbound.removeFirst();
      // Dropping is safe only because the durable log still has it. If that
      // ever stops being true, this becomes data loss.
      securityLog.record(
        SecurityEventKind.limitExceeded,
        facts: {
          'limit': 'inbound_queue',
          'sender_id': dropped.senderId,
          'depth': _inbound.length,
        },
      );
    }
    _emit(_state.copyWith(queuedInbound: _inbound.length));
    unawaited(_drain());
  }

  /// Applies queued messages one at a time.
  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_inbound.isNotEmpty && !_disposed) {
        await _applyOne(_inbound.removeFirst());
        _emit(_state.copyWith(queuedInbound: _inbound.length));
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _applyOne(CrdtMessage message) async {
    // Stage, judge, then apply. Never the other way round.
    final decision = await gate.inspect(
      senderId: message.senderId,
      update: message.payload,
    );
    if (!decision.isAllowed) {
      securityLog.record(
        decision.verdict == CrdtVerdict.refusedMalformed
            ? SecurityEventKind.protocolError
            : SecurityEventKind.authorizationFailed,
        facts: {
          'topic': crdtTopicFor(kbId),
          'sender_id': message.senderId,
          'verdict': decision.verdict.name,
          'file_id': decision.offendingFileId,
        },
      );
      if (!_refusals.isClosed) _refusals.add(decision);
      return;
    }

    try {
      final changed = await store.applyUpdate(message.payload);
      if (changed.isNotEmpty) _remoteChanges.add(changed);
    } on Object catch (error) {
      securityLog.record(
        SecurityEventKind.updateRejected,
        facts: {'sender_id': message.senderId, 'reason': 'apply_failed'},
      );
      _emit(_state.copyWith(detail: () => describeError(error)));
    }
  }

  // --------------------------------------------------------------- outbound --

  /// Call after a local edit this device is allowed to make directly.
  ///
  /// For a protected file the caller may not write, use [proposeChange]
  /// instead — ask [gate] with `mustProposeInsteadOfBroadcast` first.
  void noteLocalChange() {
    if (_disposed || !_started) return;
    _emit(_state.copyWith(pendingLocalPush: true));
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(broadcastDebounce, () => unawaited(_broadcast()));
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () => unawaited(_push()));
  }

  /// Routes a change to a protected file into the review queue.
  ///
  /// The edit is applied to a throwaway branch of the workspace rather than to
  /// canonical state, and only the resulting update is submitted. That is what
  /// keeps an unapproved change out of every other peer's document while
  /// leaving the author's own file on disk exactly as they typed it.
  ///
  /// Returns the proposal id.
  Future<String> proposeChange({
    required String fileId,
    required String text,
  }) async {
    final branch = await store.branch();
    try {
      await branch.setFileText(fileId: fileId, next: text);
      final update = await branch.diffSinceBase();
      if (isEmptyYjsUpdate(update)) {
        throw const WorkspaceStoreException('Nothing to propose.');
      }
      return await repository.submitProposal(
        kbId: kbId,
        fileId: fileId,
        update: update,
      );
    } finally {
      await branch.close();
    }
  }

  /// Approves a proposal and folds it into canonical state.
  ///
  /// Two steps by necessity: the server records the decision but cannot merge
  /// Yjs, so the approving client applies the bytes and pushes the result like
  /// any other edit.
  Future<CrdtProposalOutcome> resolveProposal({
    required String proposalId,
    required bool approve,
    String? reviewNote,
  }) async {
    final outcome = await repository.resolveProposal(
      proposalId: proposalId,
      approve: approve,
      reviewNote: reviewNote,
    );
    final update = outcome.update;
    if (outcome.approved && update != null) {
      final changed = await store.applyUpdate(update);
      if (changed.isNotEmpty) _remoteChanges.add(changed);
      noteLocalChange();
      await flush();
    }
    return outcome;
  }

  /// Sends pending local work now, regardless of the debounce. Used when a
  /// Knowledge Base closes, so the last edits are not lost with the timers.
  Future<void> flush() async {
    if (_disposed || !_started) return;
    _pushTimer?.cancel();
    _broadcastTimer?.cancel();
    await _push();
  }

  /// What this peer owes the log: everything it holds that the log does not.
  ///
  /// The first send of a session is the *whole* document, not a diff. A diff is
  /// relative to a state vector, and the only state vector this peer can name
  /// is its own — which would omit its own earlier operations, leaving every
  /// later update causally dangling and permanently unapplied on every peer.
  /// A full state send is idempotent in Yjs, so paying for one per session is
  /// the cheap way to be correct; `yjs_compact` folds the redundancy away.
  ///
  /// It also covers the case that has no other answer: content loaded from
  /// `workspace.bin` on this device that the log has never seen. A diff since
  /// the post-catch-up state vector would strand it silently.
  Future<Uint8List?> _pendingDiff() async {
    final since = _lastSentStateVector;
    if (since == null) {
      final whole = await store.encode();
      return isEmptyYjsUpdate(whole) ? null : whole;
    }
    final diff = await store.diff(since);
    return isEmptyYjsUpdate(diff) ? null : diff;
  }

  Future<void> _broadcast() async {
    final channel = _channel;
    if (_disposed || channel == null) return;
    if (_state.health != CrdtLinkHealth.connected) return;
    try {
      final diff = await _pendingDiff();
      if (diff == null) return;
      // Chunked because Realtime caps a payload at 256 KB and a first sync of
      // a real Knowledge Base is larger than that.
      final frames = encodeMessage(
        type: _lastSentStateVector == null
            ? CrdtMessageType.syncStep2
            : CrdtMessageType.crdtUpdate,
        messageId: _newMessageId(),
        senderId: authorId,
        payload: diff,
      );
      for (final frame in frames) {
        await channel.sendBroadcastMessage(
          event: kCrdtBroadcastEvent,
          payload: frame.payload,
        );
      }
    } on Object {
      // Broadcast is the lossy half by design. Whatever failed to go out lives
      // in the diff until the next push writes it durably.
    }
  }

  Future<void> _push() async {
    if (_disposed) return;
    final active = _activePush;
    if (active != null) return active;
    if (!_pushBudget.allows(_pushKey)) return;

    final operation = _performPush();
    _activePush = operation;
    try {
      await operation;
    } finally {
      if (identical(_activePush, operation)) _activePush = null;
    }
  }

  static const String _pushKey = 'workspace';

  Future<void> _performPush() async {
    try {
      final diff = await _pendingDiff();
      if (diff == null) {
        _emit(_state.copyWith(pendingLocalPush: false));
        return;
      }
      final cursor = await repository.push(kbId: kbId, update: diff);
      // Advance only after the server accepted it. If the push failed, the
      // same span is still pending and goes out with the next one, rather than
      // being silently dropped.
      _lastSentStateVector = await store.stateVector();
      _pushBudget.recordSuccess(_pushKey);
      _emit(
        _state.copyWith(
          cursor: cursor > _state.cursor ? cursor : _state.cursor,
          pendingLocalPush: false,
          health: CrdtLinkHealth.connected,
          detail: () => null,
        ),
      );
    } on Object catch (error) {
      _pushBudget.recordFailure(_pushKey);
      if (isRateLimited(error)) {
        securityLog.record(
          SecurityEventKind.limitExceeded,
          facts: {'limit': 'push_rate', 'user_id': authorId},
        );
      }
      // PT429 means the server thinks we are pushing too fast. Backing off is
      // the entire remedy; the pending diff simply grows and goes out in one
      // larger update, which is what the debounce wanted in the first place.
      _emit(
        _state.copyWith(
          health: CrdtLinkHealth.degraded,
          pendingLocalPush: true,
          detail: () => isRateLimited(error)
              ? 'Collaboration is batching edits; they are saved on this device.'
              : describeError(error),
        ),
      );
    }
  }

  void _emit(CrdtLinkState next) {
    if (_disposed) return;
    _state = next;
    if (!_states.isClosed) _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    // Send what is pending before tearing down, but never let a failing server
    // hold a Knowledge Base open.
    try {
      await flush();
    } on Object {
      // The workspace is saved to disk regardless; this only shares it.
    }
    _disposed = true;
    _pushTimer?.cancel();
    _broadcastTimer?.cancel();
    _inbound.clear();
    securityLog.record(
      SecurityEventKind.channelLeft,
      facts: {'topic': crdtTopicFor(kbId), 'user_id': authorId},
    );
    securityLog.flush();
    final channel = _channel;
    _channel = null;
    if (channel != null) await supabase.removeChannel(channel);
    await _states.close();
    await _remoteChanges.close();
    await _refusals.close();
  }
}
