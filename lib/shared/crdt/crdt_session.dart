/// Drives one Knowledge Base's CRDT collaboration for as long as it is open.
///
/// Ties three things together that each know nothing about the others: the
/// local [WorkspaceStore] (a yrs document behind the Rust bridge), the durable
/// log in Postgres, and the `crdt:<kbId>` Realtime topic. The loop is:
///
///   join  -> pull everything since the remembered cursor, apply it
///   local -> diff against the last sent state vector, broadcast it, persist it
///   remote-> apply whatever arrives, from either route
///
/// Why both routes. Broadcast is immediate and keeps no history; the log is
/// durable and debounced to seconds. A peer that was offline sees nothing of
/// the broadcast and everything of the log. Yjs updates are idempotent and
/// commutative, so receiving one twice costs nothing — which is the property
/// that lets these run at different rates without coordination.
///
/// What this deliberately does not do: it does not touch documents, revisions,
/// change_sets, or anything else the existing Supabase sync owns. Until CRDT
/// sync is proven end to end, that path stays authoritative and this one runs
/// beside it.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/retry_budget.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';

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
    this.detail,
  });

  final CrdtLinkHealth health;

  /// Position in `yjs_updates` this peer has applied everything up to.
  final int cursor;

  /// Local edits made but not yet written to the durable log.
  final bool pendingLocalPush;

  final String? detail;

  CrdtLinkState copyWith({
    CrdtLinkHealth? health,
    int? cursor,
    bool? pendingLocalPush,
    String? Function()? detail,
  }) => CrdtLinkState(
    health: health ?? this.health,
    cursor: cursor ?? this.cursor,
    pendingLocalPush: pendingLocalPush ?? this.pendingLocalPush,
    detail: detail == null ? this.detail : detail(),
  );
}

class CrdtSession {
  CrdtSession({
    required this.kbId,
    required this.store,
    required this.repository,
    required this.authorId,
    RealtimeChannel Function(String topic)? channelFactory,
    this.pushDebounce = kCrdtPushDebounce,
    this.broadcastDebounce = kCrdtBroadcastDebounce,
  }) : _channelFactory = channelFactory ?? _defaultChannel;


  final String kbId;
  final WorkspaceStore store;
  final CrdtSyncRepository repository;
  final String authorId;

  final RealtimeChannel Function(String topic) _channelFactory;

  /// How long local edits accumulate before reaching the durable log.
  final Duration pushDebounce;

  /// How long they accumulate before reaching other people's screens.
  final Duration broadcastDebounce;

  /// Pushing is automatic, so it needs the same protection as publishing: a
  /// rejected write must not be resent on a loop. One key, since the whole
  /// workspace pushes as a unit.
  final RetryBudget _pushBudget = RetryBudget();

  final _states = StreamController<CrdtLinkState>.broadcast();
  Stream<CrdtLinkState> get states => _states.stream;
  CrdtLinkState get state => _state;
  CrdtLinkState _state = const CrdtLinkState();

  /// File ids changed by updates that came from somewhere else. The caller
  /// materialises these to Markdown; this class never touches the filesystem.
  final _remoteChanges = StreamController<List<String>>.broadcast();
  Stream<List<String>> get remoteChanges => _remoteChanges.stream;

  RealtimeChannel? _channel;
  Timer? _pushTimer;
  Timer? _broadcastTimer;
  Uint8List? _lastSentStateVector;
  bool _started = false;
  bool _disposed = false;
  Future<void>? _activePush;

  static RealtimeChannel _defaultChannel(String topic) =>
      supabase.channel(topic, opts: const RealtimeChannelConfig(private: true));

  /// Catches up from the durable log, then joins the live topic.
  ///
  /// Catch-up comes first deliberately: joining first would let a broadcast
  /// land on a document that has not yet applied the history that broadcast
  /// assumes, and while Yjs tolerates that, it makes the cursor meaningless.
  Future<void> start() async {
    if (_started || _disposed) return;
    _started = true;
    _emit(_state.copyWith(health: CrdtLinkHealth.connecting, detail: () => null));

    try {
      await _catchUp();
    } on Object catch (error) {
      // A failed catch-up is not a failed session. The local document is
      // whole and still saving to disk; only sharing has stalled.
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
    final channel = _channelFactory(crdtTopicFor(kbId));
    _channel = channel;
    channel
        .onBroadcast(
          event: kCrdtBroadcastEvent,
          callback: (payload) => unawaited(_applyBroadcast(payload)),
        )
        .subscribe((status, error) {
          if (_disposed || !identical(_channel, channel)) return;
          switch (status) {
            case RealtimeSubscribeStatus.subscribed:
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
              _emit(
                _state.copyWith(
                  health: CrdtLinkHealth.degraded,
                  detail: () =>
                      error == null ? 'Live collaboration dropped.' : describeError(error),
                ),
              );
            case RealtimeSubscribeStatus.closed:
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

  Future<void> _applyBroadcast(Map<String, dynamic> payload) async {
    if (_disposed) return;
    final CrdtUpdate update;
    try {
      update = CrdtUpdate.fromRow(Map<String, Object?>.from(payload));
    } on Object {
      // An unreadable payload is ignored rather than trusted. The durable log
      // still carries whatever this was meant to be.
      return;
    }
    if (update.authorId == authorId) return;
    try {
      final changed = await store.applyUpdate(update.bytes);
      if (changed.isNotEmpty) _remoteChanges.add(changed);
    } on Object catch (error) {
      _emit(_state.copyWith(detail: () => describeError(error)));
    }
  }

  /// Call after any local edit. Schedules a broadcast and a durable push;
  /// repeated calls collapse into one of each.
  void noteLocalChange() {
    if (_disposed || !_started) return;
    _emit(_state.copyWith(pendingLocalPush: true));
    _broadcastTimer?.cancel();
    _broadcastTimer = Timer(broadcastDebounce, () => unawaited(_broadcast()));
    _pushTimer?.cancel();
    _pushTimer = Timer(pushDebounce, () => unawaited(_push()));
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
    if (_disposed || _channel == null) return;
    if (_state.health != CrdtLinkHealth.connected) return;
    try {
      final diff = await _pendingDiff();
      if (diff == null) return;
      await _channel!.sendBroadcastMessage(
        event: kCrdtBroadcastEvent,
        payload: CrdtUpdate(
          id: 0,
          authorId: authorId,
          bytes: diff,
        ).toBroadcastPayload(),
      );
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
    final channel = _channel;
    _channel = null;
    if (channel != null) await supabase.removeChannel(channel);
    await _states.close();
    await _remoteChanges.close();
  }
}
