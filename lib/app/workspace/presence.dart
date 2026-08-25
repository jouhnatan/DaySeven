/// Live presence: broadcasting where you are, and collecting where everybody
/// else is.
///
/// This runs alongside the reviewed-edit model rather than inside it. Nothing
/// here writes a table, creates a revision, or touches the sync ledger — the
/// payload is ephemeral, held by Realtime per connection and dropped when the
/// socket closes. If the whole channel fails, the app behaves exactly as it
/// did before it existed, which is why every failure below is swallowed into a
/// health value instead of surfacing as an error.
///
/// It lives in `app/workspace/` for the reason the rest of this folder does:
/// it reads the open Knowledge Base, the open document and the editing focus,
/// and the tree, the editor and the bottom bar all read it back.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
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

/// Presence needs the network, so it is off entirely without Supabase — the
/// same gate the rest of collaboration uses. A Knowledge Base that is only a
/// folder on one disk broadcasts nothing.
final presenceEnabledProvider = Provider<bool>((ref) => isSupabaseConfigured);

class PresenceController extends StateNotifier<PresenceState> {
  PresenceController(this._ref) : super(const PresenceState()) {
    _ref.listen(kbSessionProvider, (_, _) => unawaited(_bind()));
    _ref.listen(currentUserProvider, (_, _) => unawaited(_bind()));
    _ref.listen(kbRoleProvider, (_, _) => unawaited(_bind()));
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

  RealtimeChannel? _channel;
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

    // A Knowledge Base nobody shares has no channel to join. `local` is also
    // what the role resolves to while signed out or offline, so this covers
    // those without asking about them separately.
    final wanted =
        enabled &&
        kbId != null &&
        userId != null &&
        role != null &&
        role != KbRole.local &&
        role != KbRole.invited;

    if (wanted &&
        _boundKbId == kbId &&
        _boundUserId == userId &&
        _channel != null) {
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
    state = state.copyWith(peers: const {}, health: PresenceHealth.connecting);

    // A separate topic from `kb:<kbId>`, and separate on purpose: presence is
    // client-sent, so its topic is the one granted insert on
    // realtime.messages. The notification bus stays read-only, where a forged
    // event could otherwise drive a peer's sync. See the presence migration.
    final channel = supabase.channel(
      'presence:$kbId',
      opts: RealtimeChannelConfig(private: true, key: userId),
    );
    _channel = channel;

    channel
        .onPresenceSync((_) => _absorb(channel))
        .onPresenceJoin((_) => _absorb(channel))
        .onPresenceLeave((_) => _absorb(channel))
        .subscribe((status, error) {
          if (!mounted || !identical(_channel, channel)) return;
          state = state.copyWith(
            health: switch (status) {
              RealtimeSubscribeStatus.subscribed => PresenceHealth.connected,
              RealtimeSubscribeStatus.channelError ||
              RealtimeSubscribeStatus.timedOut => PresenceHealth.error,
              RealtimeSubscribeStatus.closed => PresenceHealth.inactive,
            },
          );
          if (status == RealtimeSubscribeStatus.subscribed) {
            _lastSent = null;
            _sendNow();
          }
        });
  }

  Future<void> _teardown() async {
    _sendWindow?.cancel();
    _sendWindow = null;
    _idleTimer?.cancel();
    _idleTimer = null;
    _sendPending = false;
    _idle = false;
    _lastSent = null;

    final previous = _channel;
    _channel = null;
    _boundKbId = null;
    _boundUserId = null;
    if (previous == null) return;
    try {
      await previous.untrack();
    } on Object {
      // Leaving is best-effort; the socket closing says the same thing.
    }
    try {
      await supabase.removeChannel(previous);
    } on Object {
      // Same.
    }
  }

  void _absorb(RealtimeChannel channel) {
    if (!mounted || !identical(_channel, channel)) return;
    final selfUserId = _boundUserId;
    if (selfUserId == null) return;
    try {
      final peers = peersFromPresencePayloads(
        channel.presenceState().map(
          (entry) => entry.presences.map((presence) => presence.payload),
        ),
        selfUserId: selfUserId,
      );
      state = state.copyWith(peers: peers);
    } on Object {
      // An unreadable presence state must not replace a good one.
    }
  }

  /// Where this copy of the app currently is.
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
    if (!mounted || _channel == null) return;
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
    final channel = _channel;
    if (!mounted || channel == null) return;
    final self = _self();
    if (self == null) return;
    // Saying the same thing again costs a round trip and tells nobody
    // anything.
    if (_lastSent != null && _lastSent!.samePositionAs(self)) return;
    _lastSent = self;
    unawaited(_track(channel, self));
  }

  Future<void> _track(RealtimeChannel channel, PeerPresence self) async {
    try {
      await channel.track(self.toJson());
    } on Object {
      // Presence failing is a cosmetic loss, never an error the user is shown.
      // Clear the memo so the next attempt is not skipped as a duplicate.
      if (identical(_channel, channel)) _lastSent = null;
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
