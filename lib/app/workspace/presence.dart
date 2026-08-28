/// Live presence over the Knowledge Base's Render relay connection.
///
/// This runs alongside the reviewed-edit model rather than inside it. Nothing
/// here writes a table, creates a revision, or touches the sync ledger — the
/// payload is ephemeral and dropped when the socket closes. If the relay
/// fails, the app behaves exactly as it
/// did before it existed, which is why every failure below is swallowed into a
/// health value instead of surfacing as an error.
///
/// It lives in `app/workspace/` for the reason the rest of this folder does:
/// it reads the open Knowledge Base, the open document and the editing focus,
/// and the tree, the editor and the bottom bar all read it back.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/crdt_collaboration.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/blocks/markdown.dart';
import 'package:dayseven/shared/crdt/crdt_session.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:dayseven/shared/presence/peer_presence.dart';

enum PresenceHealth { inactive, connecting, connected, error }

class PresenceState {
  const PresenceState({
    this.peers = const {},
    this.health = PresenceHealth.inactive,
  });

  /// Everyone else in this Knowledge Base, by user id. Never contains you.
  final Map<String, PeerPresence> peers;
  final PresenceHealth health;

  List<PeerPresence> get peerList => peers.values.toList(growable: false);

  PresenceState copyWith({
    Map<String, PeerPresence>? peers,
    PresenceHealth? health,
  }) =>
      PresenceState(peers: peers ?? this.peers, health: health ?? this.health);
}

/// Test seam retained for the existing controller tests.
final presenceEnabledProvider = Provider<bool>((ref) => true);

class PresenceController extends StateNotifier<PresenceState> {
  PresenceController(this._ref) : super(const PresenceState()) {
    _ref.listen(kbSessionProvider, (_, _) => unawaited(_bind()));
    _ref.listen(currentUserProvider, (_, _) => unawaited(_bind()));
    _ref.listen(kbRoleProvider, (_, _) => unawaited(_bind()));
    _ref.listen(crdtCollaborationProvider, (_, _) => unawaited(_bind()));
    _ref.listen(myProfileProvider, (_, _) => _schedulePush());
    _ref.listen<OpenDocument?>(documentControllerProvider, (previous, next) {
      // Only a change of document moves you; a keystroke does not.
      if (previous?.relativePath == next?.relativePath &&
          previous?.document.id == next?.document.id) {
        return;
      }
      _schedulePush();
    });
    _ref.listen<EditingFocus?>(editingFocusProvider, (previous, next) {
      if (previous?.blockId == next?.blockId) return;
      _schedulePush();
    });
    unawaited(_bind());
  }

  final Ref _ref;

  CrdtSession? _session;
  StreamSubscription<CrdtPresenceEvent>? _presenceEvents;
  StreamSubscription<CrdtPeerEvent>? _peerEvents;
  String? _boundKbId;
  String? _boundUserId;

  /// The editor republishes its focus on every selection change, and a
  /// selection changes on every keystroke. Without this, typing a sentence
  /// would be a send per character.
  static const _minSendInterval = Duration(milliseconds: 400);

  /// Long enough that thinking does not read as absence, short enough that a
  /// dot left by somebody who walked away stops claiming they are there.
  static const _idleAfter = Duration(minutes: 5);

  Timer? _sendWindow;
  Timer? _idleTimer;
  bool _sendPending = false;
  bool _idle = false;
  PeerPresence? _lastSent;

  Future<void> _bind() async {
    final session = _ref.read(kbSessionProvider);
    final user = _ref.read(currentUserProvider);
    final enabled = _ref.read(presenceEnabledProvider);
    final role = _ref.read(kbRoleProvider).valueOrNull;
    final kbId = session?.kb.manifest.kbId;
    final userId = user?.id;
    final collaboration = _ref.read(crdtCollaborationProvider);
    final crdtSession = collaboration.session;

    // A Knowledge Base nobody shares has no channel to join. `local` is also
    // what the role resolves to while signed out or offline, so this covers
    // those without asking about them separately.
    final wanted =
        enabled &&
        kbId != null &&
        userId != null &&
        role != null &&
        role != KbRole.local &&
        role != KbRole.invited &&
        crdtSession != null;

    if (wanted &&
        _boundKbId == kbId &&
        _boundUserId == userId &&
        identical(_session, crdtSession)) {
      final nextHealth = _healthFor(collaboration.linkState.connection);
      if (state.health != nextHealth) {
        state = state.copyWith(
          peers: nextHealth == PresenceHealth.connected ? null : const {},
          health: nextHealth,
        );
        if (nextHealth == PresenceHealth.connected) {
          _lastSent = null;
          _sendNow();
        }
      }
      return;
    }

    await _teardown();
    if (!mounted || !wanted) {
      if (mounted) {
        state = const PresenceState(health: PresenceHealth.inactive);
      }
      return;
    }

    _boundKbId = kbId;
    _boundUserId = userId;
    _session = crdtSession;
    state = state.copyWith(
      peers: const {},
      health: _healthFor(collaboration.linkState.connection),
    );
    _presenceEvents = crdtSession.presenceEvents.listen(_absorb);
    _peerEvents = crdtSession.peerEvents.listen((event) {
      if (!mounted || !identical(_session, crdtSession)) return;
      if (event.kind == CrdtPeerEventKind.left) {
        final peers = {...state.peers}..remove(event.userId);
        state = state.copyWith(peers: peers);
      }
    });
    if (state.health == PresenceHealth.connected) _sendNow();
  }

  PresenceHealth _healthFor(CrdtConnectionState connection) =>
      switch (connection) {
        CrdtConnectionState.connected => PresenceHealth.connected,
        CrdtConnectionState.connecting => PresenceHealth.connecting,
        CrdtConnectionState.disconnected => PresenceHealth.inactive,
        CrdtConnectionState.error => PresenceHealth.error,
      };

  Future<void> _teardown() async {
    _sendWindow?.cancel();
    _sendWindow = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _sendPending = false;
    _idle = false;
    _lastSent = null;

    await _presenceEvents?.cancel();
    _presenceEvents = null;
    await _peerEvents?.cancel();
    _peerEvents = null;
    _session = null;
    _boundKbId = null;
    _boundUserId = null;
  }

  void _absorb(CrdtPresenceEvent event) {
    if (!mounted || _session == null) return;
    final selfUserId = _boundUserId;
    if (selfUserId == null) return;
    try {
      final peer = PeerPresence.fromJson({
        ...event.payload,
        // Identity comes from the relay's authenticated metadata, never from
        // the sender-controlled JSON body.
        'user_id': event.userId,
      });
      if (peer == null || peer.userId == selfUserId) return;
      state = state.copyWith(
        peers: {...state.peers, peer.userId: peer},
      );
    } on Object {
      // An unreadable presence payload must not replace a good one.
    }
  }

  /// Where this copy of the app currently is.
  /// Turns the caret's block-relative offset into a file-relative Yjs anchor.
  ///
  /// Returns nulls whenever anything does not line up — no collaboration
  /// running, no CRDT copy of this file, the editor and the document briefly
  /// disagreeing after an external edit. A cursor drawn in the wrong place is
  /// worse than one not drawn, and presence has never been allowed to fail
  /// loudly.
  Future<({String? cursor, String? anchor})> _caretAnchors() async {
    const none = (cursor: null, anchor: null);
    final collaboration = _ref.read(crdtCollaborationProvider);
    final awareness = collaboration.awareness;
    if (awareness == null) return none;

    final open = _ref.read(documentControllerProvider);
    final focus = _ref.read(editingFocusProvider);
    if (open == null || focus == null) return none;
    final caret = focus.caretOffset;
    if (caret == null) return none;

    final blockStart = markdownBodyOffsetOfBlock(
      encodeMarkdown(open.document),
      focus.blockId,
    );
    if (blockStart == null) return none;

    final fileId = open.document.id;
    final cursor = await awareness.encodeCaret(
      fileId: fileId,
      offset: blockStart + caret,
    );
    final anchorOffset = focus.selectionAnchorOffset;
    final anchor = anchorOffset == null
        ? null
        : await awareness.encodeCaret(
            fileId: fileId,
            offset: blockStart + anchorOffset,
          );
    return (cursor: cursor, anchor: anchor);
  }

  PeerPresence? _self() {
    final user = _ref.read(currentUserProvider);
    if (user == null) return null;
    final profile = _ref.read(myProfileProvider).valueOrNull;
    final metadata = user.userMetadata ?? const {};
    final open = _ref.read(documentControllerProvider);
    final focus = _ref.read(editingFocusProvider);

    return PeerPresence(
      userId: user.id,
      username: profile?.username ?? (metadata['username'] as String?) ?? '',
      displayName:
          profile?.displayName ??
          (metadata['display_name'] as String?) ??
          (metadata['username'] as String?) ??
          '',
      relativePath: open?.relativePath,
      documentId: open?.document.id,
      // The focus belongs to the open document; without one it means nothing.
      blockId: open == null ? null : focus?.blockId,
      idle: _idle,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  /// Rate-limits sends: one immediately, then at most one per window, with a
  /// trailing send so the last position is never the one that got dropped.
  void _schedulePush() {
    if (!mounted || _session == null) return;
    _idle = false;
    _restartIdleTimer();

    if (_sendWindow != null) {
      _sendPending = true;
      return;
    }
    _sendNow();
    _sendWindow = Timer(_minSendInterval, () {
      _sendWindow = null;
      if (!_sendPending) return;
      _sendPending = false;
      _schedulePush();
    });
  }

  void _restartIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleAfter, () {
      if (!mounted || _idle) return;
      _idle = true;
      _sendNow();
    });
  }

  void _sendNow() {
    final session = _session;
    if (!mounted || session == null) return;
    final self = _self();
    if (self == null) return;
    // Saying the same thing again costs a round trip and tells nobody
    // anything. Compared before the anchors are computed, so a repeat costs
    // nothing at all.
    if (_lastSent != null && _lastSent!.samePositionAs(self)) return;
    _lastSent = self;
    unawaited(_trackWithCaret(session, self));
  }

  Future<void> _trackWithCaret(
    CrdtSession session,
    PeerPresence self,
  ) async {
    final anchors = await _caretAnchors();
    if (!mounted || !identical(_session, session)) return;
    final withCaret = self.copyWith(
      cursor: () => anchors.cursor,
      selectionAnchor: () => anchors.anchor,
    );
    _lastSent = withCaret;
    await _track(session, withCaret);
  }

  Future<void> _track(CrdtSession session, PeerPresence self) async {
    try {
      await session.sendPresence(self.toJson());
    } on Object {
      // Presence failing is a cosmetic loss, never an error the user is shown.
      // Clear the memo so the next attempt is not skipped as a duplicate.
      if (identical(_session, session)) _lastSent = null;
    }
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }
}

final presenceControllerProvider =
    StateNotifierProvider<PresenceController, PresenceState>(
      PresenceController.new,
    );

/// Collaborators grouped by the document they are in, for the tree.
///
/// Keyed by path rather than by document id because that is what the tree
/// rows have, and because a path keeps working when the two copies have
/// drifted apart.
final peersByPathProvider = Provider<Map<String, List<PeerPresence>>>(
  (ref) => peersByPath(ref.watch(presenceControllerProvider).peerList),
);

/// Everybody in the document that is currently open, whether or not their
/// block exists in this copy of it.
final peersInOpenDocumentProvider = Provider<List<PeerPresence>>((ref) {
  final open = ref.watch(documentControllerProvider);
  if (open == null) return const [];
  return ref.watch(peersByPathProvider)[open.relativePath] ?? const [];
});

/// Collaborators in the open document, grouped by the block they are in.
///
/// Peers on a block this copy does not have are absent here by design; they
/// are still counted by [peersInOpenDocumentProvider], which is what the
/// bottom bar shows.
final peersByBlockProvider = Provider<Map<String, List<PeerPresence>>>((ref) {
  final open = ref.watch(documentControllerProvider);
  if (open == null) return const {};
  return peersByBlock(
    ref.watch(presenceControllerProvider).peerList,
    relativePath: open.relativePath,
    knownBlockIds: {for (final block in open.document.blocks) block.id},
  );
});
