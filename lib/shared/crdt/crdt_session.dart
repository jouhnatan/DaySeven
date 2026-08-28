/// Local-first CRDT collaboration over the Render WebSocket relay.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import 'package:dayseven/shared/crdt/collaboration_journal.dart';
import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/security/security_log.dart';

const int kMaxInboundQueue = 64;

/// Compatibility view used by existing UI while it moves to the exact socket
/// state exposed in [CrdtLinkState.connection].
enum CrdtLinkHealth { inactive, connecting, connected, degraded }

class CrdtLinkState {
  const CrdtLinkState({
    this.connection = CrdtConnectionState.disconnected,
    this.pendingLocalPush = false,
    this.queuedInbound = 0,
    this.waitingForPeer = false,
    this.detail,
  });

  final CrdtConnectionState connection;
  final bool pendingLocalPush;
  final int queuedInbound;

  /// True after connecting/reconciling until another authenticated room peer
  /// is observed. The UI uses this for first-device bootstrap guidance.
  final bool waitingForPeer;
  final String? detail;

  CrdtLinkHealth get health => switch (connection) {
    CrdtConnectionState.connected => CrdtLinkHealth.connected,
    CrdtConnectionState.connecting => CrdtLinkHealth.connecting,
    CrdtConnectionState.disconnected => CrdtLinkHealth.inactive,
    CrdtConnectionState.error => CrdtLinkHealth.degraded,
  };

  /// The durable Postgres cursor no longer exists. Kept temporarily so older
  /// UI code can compile during the transport cutover.
  int get cursor => 0;

  CrdtLinkState copyWith({
    CrdtConnectionState? connection,
    bool? pendingLocalPush,
    int? queuedInbound,
    bool? waitingForPeer,
    String? Function()? detail,
  }) => CrdtLinkState(
    connection: connection ?? this.connection,
    pendingLocalPush: pendingLocalPush ?? this.pendingLocalPush,
    queuedInbound: queuedInbound ?? this.queuedInbound,
    waitingForPeer: waitingForPeer ?? this.waitingForPeer,
    detail: detail == null ? this.detail : detail(),
  );
}

enum CrdtPeerEventKind { joined, left }

class CrdtPeerEvent {
  const CrdtPeerEvent({required this.kind, required this.userId, this.role});
  final CrdtPeerEventKind kind;
  final String userId;
  final String? role;
}

class CrdtPresenceEvent {
  CrdtPresenceEvent({
    required this.userId,
    required this.role,
    required Map<String, Object?> payload,
  }) : payload = Map.unmodifiable(payload);

  final String userId;
  final String? role;
  final Map<String, Object?> payload;
}

enum CollaborationProposalEventKind { received, resolved }

class CollaborationProposalEvent {
  const CollaborationProposalEvent.received(this.proposal)
    : kind = CollaborationProposalEventKind.received,
      resolution = null;
  const CollaborationProposalEvent.resolved(this.resolution)
    : kind = CollaborationProposalEventKind.resolved,
      proposal = null;

  final CollaborationProposalEventKind kind;
  final CollaborationProposal? proposal;
  final CollaborationResolution? resolution;
}

class CrdtSession {
  CrdtSession({
    required this.kbId,
    required this.store,
    required this.authorId,
    required this.gate,
    required this.transport,
    required this.journal,
    SecurityLog? securityLog,
    this.maxInboundQueue = kMaxInboundQueue,
  }) : securityLog = securityLog ?? SecurityLog(sink: const NullSecuritySink());

  final String kbId;
  final WorkspaceStore store;
  final String authorId;
  final CrdtAuthorizationGate gate;
  final CrdtTransport transport;
  final CollaborationJournal journal;
  final SecurityLog securityLog;
  final int maxInboundQueue;

  final Queue<CrdtEnvelope> _inbound = Queue();
  final Set<String> _peers = {};
  final Map<String, CollaborationResolution> _orphanResolutions = {};
  final Uuid _uuid = const Uuid();

  final _states = StreamController<CrdtLinkState>.broadcast();
  final _remoteChanges = StreamController<List<String>>.broadcast();
  final _refusals = StreamController<CrdtDecision>.broadcast();
  final _peerEvents = StreamController<CrdtPeerEvent>.broadcast();
  final _presenceEvents = StreamController<CrdtPresenceEvent>.broadcast();
  final _proposalEvents =
      StreamController<CollaborationProposalEvent>.broadcast();

  Stream<CrdtLinkState> get states => _states.stream;
  Stream<List<String>> get remoteChanges => _remoteChanges.stream;
  Stream<CrdtDecision> get refusals => _refusals.stream;
  Stream<CrdtPeerEvent> get peerEvents => _peerEvents.stream;
  Stream<CrdtPresenceEvent> get presenceEvents => _presenceEvents.stream;
  Stream<CollaborationProposalEvent> get proposalEvents =>
      _proposalEvents.stream;

  CrdtLinkState get state => _state;
  CrdtLinkState _state = const CrdtLinkState();

  StreamSubscription<CrdtConnectionState>? _stateSubscription;
  StreamSubscription<CrdtEnvelope>? _eventSubscription;
  StreamSubscription<CrdtTransportError>? _errorSubscription;
  Uint8List? _lastOutboundVector;
  Future<void>? _activeDrain;
  Future<void>? _queuedDrain;
  Future<void>? _activeLocalQueue;
  bool _started = false;
  bool _disposed = false;
  bool _draining = false;
  bool _pendingLocal = false;

  Future<void> start() => connect();

  Future<void> connect() async {
    if (_disposed) throw StateError('CrdtSession is disposed.');
    if (!_started) {
      _started = true;
      _stateSubscription = transport.states.listen(_onConnectionState);
      _eventSubscription = transport.events.listen(_receive);
      _errorSubscription = transport.errors.listen((error) {
        _emit(_state.copyWith(detail: () => error.message));
        if (error.rejection != null) {
          securityLog.record(
            SecurityEventKind.protocolError,
            facts: {'reason': error.rejection!.name},
          );
        }
      });
    }
    _emit(
      _state.copyWith(
        connection: CrdtConnectionState.connecting,
        detail: () => null,
      ),
    );
    await transport.connect();
    // A fake transport may already be connected and have emitted before this
    // session subscribed. Reflect its current state explicitly.
    _onConnectionState(transport.state);
  }

  Future<void> disconnect() async {
    if (!_started) return;
    await transport.disconnect();
    _peers.clear();
    _emit(
      _state.copyWith(
        connection: CrdtConnectionState.disconnected,
        waitingForPeer: false,
      ),
    );
  }

  void _onConnectionState(CrdtConnectionState connection) {
    if (_disposed) return;
    if (_state.connection == connection) return;
    final waiting = connection == CrdtConnectionState.connected
        ? _peers.isEmpty
        : false;
    _emit(
      _state.copyWith(
        connection: connection,
        waitingForPeer: waiting,
        detail: () => connection == CrdtConnectionState.error
            ? _state.detail ?? 'Collaboration connection failed.'
            : null,
      ),
    );
    if (connection != CrdtConnectionState.connected) {
      // The socket is gone; any acknowledgement it owed us died with it.
      journal.requeueInFlight();
    }
    if (connection == CrdtConnectionState.connected) {
      securityLog.record(
        SecurityEventKind.channelJoined,
        facts: {'room_id': kbId, 'user_id': authorId},
      );
      unawaited(_afterConnected());
    }
  }

  Future<void> _afterConnected() async {
    await reconcile();
    await _sendProposalInventory();
    await _drainOutbox();
  }

  /// Explicit state-vector reconciliation, used by the manual Sync action.
  Future<void> reconcile() async {
    if (transport.state != CrdtConnectionState.connected) return;
    _emit(_state.copyWith(waitingForPeer: _peers.isEmpty));
    await transport.reconcile(await store.stateVector());
  }

  void _receive(CrdtEnvelope message) {
    if (_disposed) return;
    _inbound.addLast(message);
    var dropped = false;
    while (_inbound.length > maxInboundQueue) {
      _inbound.removeFirst();
      dropped = true;
    }
    if (dropped) {
      securityLog.record(
        SecurityEventKind.limitExceeded,
        facts: {'limit': 'inbound_queue', 'depth': _inbound.length},
      );
      // Unlike the old durable Postgres log, the relay cannot replay a dropped
      // frame. State-vector reconciliation recovers it from a live peer.
      unawaited(reconcile());
    }
    _emit(_state.copyWith(queuedInbound: _inbound.length));
    unawaited(_drain());
  }

  Future<void> _drain() async {
    if (_draining || _disposed) return;
    _draining = true;
    try {
      while (_inbound.isNotEmpty && !_disposed) {
        final message = _inbound.removeFirst();
        await _handle(message);
        _emit(_state.copyWith(queuedInbound: _inbound.length));
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _handle(CrdtEnvelope message) async {
    final senderId = message.senderId;
    if (senderId != null && senderId != authorId) {
      _peers.add(senderId);
      _emit(_state.copyWith(waitingForPeer: false));
    }
    switch (message.opcode) {
      case CrdtOpcode.peerJoined:
        if (senderId == null || senderId == authorId) return;
        _peerEvents.add(
          CrdtPeerEvent(
            kind: CrdtPeerEventKind.joined,
            userId: senderId,
            role: message.senderRole,
          ),
        );
        await reconcile();
        await _sendProposalInventory();
      case CrdtOpcode.peerLeft:
        if (senderId == null || senderId == authorId) return;
        _peers.remove(senderId);
        _peerEvents.add(
          CrdtPeerEvent(
            kind: CrdtPeerEventKind.left,
            userId: senderId,
            role: message.senderRole,
          ),
        );
        _emit(_state.copyWith(waitingForPeer: _peers.isEmpty));
      case CrdtOpcode.stateVectorRequest:
        if (senderId == null || senderId == authorId) return;
        final update = await store.diff(message.body);
        if (!_isEmptyYjsUpdate(update)) {
          await _sendOrQueue(
            opcode: CrdtOpcode.crdtUpdate,
            metadata: {'inReplyTo': message.messageId},
            body: update,
            durable: false,
          );
        }
        await _ack(message);
      case CrdtOpcode.crdtUpdate:
        if (senderId == null || senderId == authorId) return;
        await _applyRemoteUpdate(message, senderId);
        await _ack(message);
      case CrdtOpcode.proposalInventory:
        await _receiveProposalInventory(message);
      case CrdtOpcode.proposalRequest:
        await _receiveProposalRequest(message);
      case CrdtOpcode.proposalData:
        await _receiveProposalData(message);
        await _ack(message);
      case CrdtOpcode.proposalResolution:
        await _receiveResolution(message);
        await _ack(message);
      case CrdtOpcode.presence:
        _receivePresence(message);
      case CrdtOpcode.ack:
        final acked = message.metadata['ackedMessageId'];
        if (acked is String) journal.acknowledge(acked);
      case CrdtOpcode.error:
        final detail = message.metadata['message'];
        _emit(
          _state.copyWith(
            detail: () =>
                detail is String ? detail : 'The relay refused a message.',
          ),
        );
    }
  }

  Future<void> _applyRemoteUpdate(CrdtEnvelope message, String senderId) async {
    // Capture pending local work before the inbound mutation changes the
    // workspace state vector. Inbound application itself never invokes
    // noteLocalChange, which prevents the ordinary echo loop.
    if (_pendingLocal) await _queueLocalDiff();
    final active = _activeLocalQueue;
    if (active != null) await active;

    final decision = await gate.inspect(
      senderId: senderId,
      update: message.body,
    );
    if (!decision.isAllowed) {
      securityLog.record(
        decision.verdict == CrdtVerdict.refusedMalformed
            ? SecurityEventKind.protocolError
            : SecurityEventKind.authorizationFailed,
        facts: {
          'room_id': kbId,
          'sender_id': senderId,
          'verdict': decision.verdict.name,
          'file_id': decision.offendingFileId,
        },
      );
      _refusals.add(decision);
      return;
    }
    try {
      final changed = await store.applyUpdate(message.body);
      // Make inbound state the baseline without scheduling an outbound send.
      // If a local edit was reported during the await, preserve its pending
      // baseline instead of swallowing it.
      if (!_pendingLocal) _lastOutboundVector = await store.stateVector();
      if (changed.isNotEmpty) _remoteChanges.add(changed);
    } on Object {
      securityLog.record(
        SecurityEventKind.updateRejected,
        facts: {'sender_id': senderId, 'reason': 'apply_failed'},
      );
    }
  }

  void noteLocalChange() {
    if (_disposed) return;
    _pendingLocal = true;
    _emit(_state.copyWith(pendingLocalPush: true));
    unawaited(_queueLocalDiff().then((_) => _drainOutbox()));
  }

  Future<void> _queueLocalDiff() async {
    final active = _activeLocalQueue;
    if (active != null) return active;
    late final Future<void> operation;
    operation = _performQueueLocalDiff().whenComplete(() {
      if (identical(_activeLocalQueue, operation)) _activeLocalQueue = null;
    });
    _activeLocalQueue = operation;
    return operation;
  }

  Future<void> _performQueueLocalDiff() async {
    if (!_pendingLocal) return;
    final since = _lastOutboundVector;
    final update = since == null
        ? await store.encode()
        : await store.diff(since);
    if (!_isEmptyYjsUpdate(update)) {
      journal.enqueue(opcode: CrdtOpcode.crdtUpdate, body: update);
    }
    _lastOutboundVector = await store.stateVector();
    _pendingLocal = false;
    _emit(_state.copyWith(pendingLocalPush: false));
  }

  Future<String> proposeChange({
    required String fileId,
    required String text,
  }) async {
    final baseSnapshot = await store.encode();
    final branch = await store.branch();
    try {
      await branch.setFileText(fileId: fileId, next: text);
      final update = await branch.diffSinceBase();
      if (_isEmptyYjsUpdate(update)) {
        throw const WorkspaceStoreException('Nothing to propose.');
      }
      final proposal = CollaborationProposal(
        proposalId: _uuid.v7(),
        fileId: fileId,
        authorId: authorId,
        baseSnapshot: baseSnapshot,
        update: update,
        createdAt: DateTime.now().toUtc(),
      );
      journal.saveProposal(proposal);
      journal.enqueue(
        opcode: CrdtOpcode.proposalData,
        metadata: {'proposalId': proposal.proposalId},
        body: encodeProposalPayload(proposal),
      );
      _proposalEvents.add(CollaborationProposalEvent.received(proposal));
      await _drainOutbox();
      return proposal.proposalId;
    } finally {
      await branch.close();
    }
  }

  Future<CollaborationResolution> resolveProposal({
    required String proposalId,
    required bool approve,
    String? reviewNote,
    List<int>? resolvedUpdate,
  }) async {
    final proposal = journal.proposal(proposalId);
    if (proposal == null) throw StateError('Unknown proposal $proposalId.');
    final status = approve
        ? CollaborationResolutionStatus.approved
        : CollaborationResolutionStatus.rejected;
    final canonicalUpdate = approve
        ? Uint8List.fromList(resolvedUpdate ?? proposal.update)
        : null;
    if (canonicalUpdate != null) {
      final staged = await store.stageApplyUpdate(canonicalUpdate);
      if (staged.isEmpty && !_isEmptyYjsUpdate(canonicalUpdate)) {
        // A causally-known update can legitimately touch nothing. It is still
        // safe to resolve and relay because Yjs application is idempotent.
      }
    }
    final resolution = CollaborationResolution(
      proposalId: proposalId,
      status: status,
      resolvedBy: authorId,
      resolvedAt: DateTime.now().toUtc(),
      note: reviewNote,
    );
    final write = journal.recordResolution(resolution);
    if (!write.accepted) return write.resolution;

    if (canonicalUpdate != null) {
      final changed = await store.applyUpdate(canonicalUpdate);
      if (changed.isNotEmpty) _remoteChanges.add(changed);
      journal.enqueue(opcode: CrdtOpcode.crdtUpdate, body: canonicalUpdate);
      _lastOutboundVector = await store.stateVector();
    }
    journal.enqueue(
      opcode: CrdtOpcode.proposalResolution,
      metadata: {
        'proposalId': proposalId,
        'status': status.name,
        'note': ?reviewNote,
      },
    );
    _proposalEvents.add(CollaborationProposalEvent.resolved(resolution));
    await _drainOutbox();
    return resolution;
  }

  Future<void> sendPresence(Map<String, Object?> presence) async {
    if (transport.state != CrdtConnectionState.connected) return;
    try {
      await transport.send(
        opcode: CrdtOpcode.presence,
        body: utf8.encode(jsonEncode(presence)),
      );
    } on Object {
      // Presence is explicitly ephemeral and best-effort.
    }
  }

  void _receivePresence(CrdtEnvelope message) {
    final senderId = message.senderId;
    if (senderId == null || senderId == authorId) return;
    try {
      final decoded = jsonDecode(utf8.decode(message.body));
      if (decoded is! Map) return;
      _presenceEvents.add(
        CrdtPresenceEvent(
          userId: senderId,
          role: message.senderRole,
          payload: Map<String, Object?>.from(decoded),
        ),
      );
    } on Object {
      // Malformed presence is chrome failure, never document failure.
    }
  }

  Future<void> _sendProposalInventory() async {
    if (transport.state != CrdtConnectionState.connected) return;
    final resolvedIds = [
      for (final resolution in journal.resolutions()) resolution.proposalId,
    ];
    await transport.send(
      opcode: CrdtOpcode.proposalInventory,
      metadata: {
        'proposalIds': journal.proposalIds(),
        // A hint only. Resolution authority is still enforced by replaying a
        // proposal-resolution opcode; this list merely tells a stale peer to
        // request that replay even when it already has the proposal bytes.
        'resolvedProposalIds': resolvedIds,
      },
    );
  }

  Future<void> _receiveProposalInventory(CrdtEnvelope message) async {
    final ids = message.metadata['proposalIds'];
    if (ids is! List) return;
    final resolved = message.metadata['resolvedProposalIds'];
    final resolvedIds = resolved is List
        ? resolved.whereType<String>().toSet()
        : const <String>{};
    for (final id in ids.whereType<String>()) {
      if (journal.proposal(id) == null ||
          (resolvedIds.contains(id) && journal.resolution(id) == null)) {
        await transport.send(
          opcode: CrdtOpcode.proposalRequest,
          metadata: {'proposalId': id},
        );
      }
    }
  }

  Future<void> _receiveProposalRequest(CrdtEnvelope message) async {
    final id = message.metadata['proposalId'];
    if (id is! String) return;
    final proposal = journal.proposal(id);
    if (proposal == null) return;
    await _sendOrQueue(
      opcode: CrdtOpcode.proposalData,
      metadata: {'proposalId': id},
      body: encodeProposalPayload(proposal),
      durable: false,
    );
    final resolution = journal.resolution(id);
    if (resolution != null &&
        transport.state == CrdtConnectionState.connected) {
      // The relay independently verifies that this socket currently holds a
      // reviewer-capable role before forwarding the durable local record.
      await transport.send(
        opcode: CrdtOpcode.proposalResolution,
        metadata: {
          'proposalId': id,
          'status': resolution.status.name,
          'note': ?resolution.note,
        },
      );
    }
  }

  Future<void> _receiveProposalData(CrdtEnvelope message) async {
    final id = message.metadata['proposalId'];
    final sender = message.senderId;
    if (id is! String || sender == null || sender == authorId) return;
    try {
      final proposal = decodeProposalPayload(
        proposalId: id,
        authorId: sender,
        payload: message.body,
      );
      journal.saveProposal(proposal);
      _proposalEvents.add(CollaborationProposalEvent.received(proposal));
      final orphan = _orphanResolutions.remove(id);
      if (orphan != null) _recordRemoteResolution(orphan);
    } on Object {
      securityLog.record(
        SecurityEventKind.protocolError,
        facts: {'reason': 'invalid_proposal', 'sender_id': sender},
      );
    }
  }

  Future<void> _receiveResolution(CrdtEnvelope message) async {
    final id = message.metadata['proposalId'];
    final status = message.metadata['status'];
    final sender = message.senderId;
    if (id is! String || status is! String || sender == null) return;
    final resolution = CollaborationResolution(
      proposalId: id,
      status: CollaborationResolutionStatus.fromWire(status),
      resolvedBy: sender,
      resolvedAt: DateTime.now().toUtc(),
      note: message.metadata['note'] as String?,
    );
    if (journal.proposal(id) == null) {
      if (_orphanResolutions.length >= 64) {
        _orphanResolutions.remove(_orphanResolutions.keys.first);
      }
      _orphanResolutions[id] = resolution;
      await transport.send(
        opcode: CrdtOpcode.proposalRequest,
        metadata: {'proposalId': id},
      );
      return;
    }
    _recordRemoteResolution(resolution);
  }

  void _recordRemoteResolution(CollaborationResolution resolution) {
    final write = journal.recordResolution(resolution);
    if (write.accepted) {
      _proposalEvents.add(
        CollaborationProposalEvent.resolved(write.resolution),
      );
    }
  }

  Future<void> _ack(CrdtEnvelope message) async {
    if (message.messageId == null ||
        transport.state != CrdtConnectionState.connected) {
      return;
    }
    try {
      await transport.send(
        opcode: CrdtOpcode.ack,
        metadata: {'ackedMessageId': message.messageId},
      );
    } on Object {
      // Reconciliation and proposal inventory recover a lost acknowledgement.
    }
  }

  Future<void> _sendOrQueue({
    required CrdtOpcode opcode,
    Map<String, Object?> metadata = const {},
    List<int> body = const [],
    required bool durable,
  }) async {
    if (durable) {
      journal.enqueue(opcode: opcode, metadata: metadata, body: body);
      await _drainOutbox();
      return;
    }
    if (transport.state != CrdtConnectionState.connected) return;
    await transport.send(opcode: opcode, metadata: metadata, body: body);
  }

  /// Serialises outbox drains. Two concurrent drains each read the same
  /// pending rows and send every one of them twice, because an entry only
  /// leaves the outbox once the relay acknowledges it.
  Future<void> _drainOutbox() {
    final active = _activeDrain;
    if (active == null) {
      late final Future<void> operation;
      operation = _performDrainOutbox().whenComplete(() {
        if (identical(_activeDrain, operation)) _activeDrain = null;
      });
      _activeDrain = operation;
      return operation;
    }
    // Collapse every caller arriving mid-drain onto one follow-up pass, so
    // entries enqueued after the running drain began are still delivered.
    final queued = _queuedDrain;
    if (queued != null) return queued;
    late final Future<void> follow;
    follow = active.then((_) {
      if (identical(_queuedDrain, follow)) _queuedDrain = null;
      return _drainOutbox();
    });
    _queuedDrain = follow;
    return follow;
  }

  Future<void> _performDrainOutbox() async {
    if (transport.state != CrdtConnectionState.connected) return;
    for (final entry in journal.sendableOutbox()) {
      if (transport.state != CrdtConnectionState.connected) return;
      try {
        final messageId = await transport.send(
          opcode: entry.opcode,
          metadata: entry.metadata,
          body: entry.body,
        );
        journal.markAttempt(entry.id, messageId);
      } on Object {
        return;
      }
    }
  }

  Future<void> flush() async {
    if (_disposed) return;
    if (_pendingLocal) await _queueLocalDiff();
    await _drainOutbox();
  }

  void _emit(CrdtLinkState next) {
    if (_disposed) return;
    _state = next;
    _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    try {
      await flush();
    } on Object {
      // Local workspace and outbox already contain the work.
    }
    await disconnect();
    _disposed = true;
    _inbound.clear();
    await _stateSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _errorSubscription?.cancel();
    securityLog.record(
      SecurityEventKind.channelLeft,
      facts: {'room_id': kbId, 'user_id': authorId},
    );
    securityLog.flush();
    journal.close();
    await _states.close();
    await _remoteChanges.close();
    await _refusals.close();
    await _peerEvents.close();
    await _presenceEvents.close();
    await _proposalEvents.close();
  }
}

/// Yjs encodes an empty v1 update as two bytes (zero structs, zero delete set).
bool _isEmptyYjsUpdate(List<int> update) => update.length <= 2;
