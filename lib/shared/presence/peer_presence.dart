/// Where a collaborator is: which document they have open, and which block
/// their caret is in.
///
/// This is the whole wire format of the presence channel. It carries
/// identifiers — a user, a path, a document id, a block id — and never any
/// document content, which is the same rule the `kb:<uuid>` notification bus
/// follows. Presence is ephemeral: Realtime holds it per connection and drops
/// it when the socket closes, so nothing here is ever persisted.
///
/// Awareness rides here too, as Yjs relative positions. A relative position is
/// an *anchor*, not text: it names the character a caret sits beside by its
/// CRDT identity. Somebody who does not already have that character learns
/// nothing from it, which is why cursors can travel on the same channel as
/// everything else here without the content rule bending.
library;

/// A collaborator's position, as broadcast by their copy of the app.
class PeerPresence {
  const PeerPresence({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.updatedAt,
    this.relativePath,
    this.documentId,
    this.blockId,
    this.idle = false,
    this.cursor,
    this.selectionAnchor,
  });

  final String userId;
  final String username;
  final String displayName;

  /// The document they have open, `documents/`-relative and POSIX-style, or
  /// null when they have none open. This is what the Knowledge Base tree keys
  /// on, and it keeps working when the two replicas have drifted apart.
  final String? relativePath;

  /// The same document by identity. A rename in flight can leave this pointing
  /// at a document whose path has moved under it.
  final String? documentId;

  /// The block their caret is in. Block ids are stable across edits, which is
  /// why position is a block rather than a line or a character offset: a
  /// paragraph that moves keeps its id, and an offset into their copy of the
  /// text can address text that does not exist in yours until a proposal is
  /// approved.
  final String? blockId;

  /// Set by their own copy after it has sat untouched long enough that the
  /// person has probably walked away. A closed laptop drops presence by
  /// itself; this covers the one left open.
  final bool idle;

  /// Their caret, as a Yjs *relative* position, base64-encoded.
  ///
  /// Not an index. An absolute offset is meaningless by the time it arrives:
  /// the receiver's copy has moved on, and character 40 in their document is
  /// somewhere else. A relative position is anchored to the character it sits
  /// beside, so it resolves to where the person actually is — and resolves to
  /// nothing when that text no longer exists, which is the honest answer.
  ///
  /// Only meaningful for a file both copies share through the CRDT. It is
  /// null for a document that has never synced, and null for the older builds
  /// that do not send it. [blockId] remains the coarse fallback, and is what
  /// gets drawn when this cannot be resolved.
  final String? cursor;

  /// The other end of a selection, same encoding. Null at a collapsed caret.
  final String? selectionAnchor;

  /// When their copy last sent this. Used to pick between two connections of
  /// the same person, not to expire anyone — Realtime handles departure.
  final DateTime updatedAt;

  /// The initial shown in the dot. Falls back through display name, username,
  /// and finally a neutral mark, so a peer is never drawn blank.
  String get initial {
    for (final source in [displayName, username]) {
      final trimmed = source.trim();
      if (trimmed.isNotEmpty) return trimmed.substring(0, 1).toUpperCase();
    }
    return '?';
  }

  /// What to call them in a tooltip.
  String get label {
    final name = displayName.trim();
    return name.isEmpty ? '@${username.trim()}' : name;
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'username': username,
    'display_name': displayName,
    if (relativePath != null) 'path': relativePath,
    if (documentId != null) 'document_id': documentId,
    if (blockId != null) 'block_id': blockId,
    if (cursor != null) 'cursor': cursor,
    if (selectionAnchor != null) 'selection_anchor': selectionAnchor,
    if (idle) 'idle': true,
    'updated_at': updatedAt.toUtc().toIso8601String(),
  };

  /// Returns null rather than throwing on anything unrecognised. A payload
  /// from a newer or older build must never take the panel down; the same
  /// tolerance the `proposal_created` handler already applies.
  static PeerPresence? fromJson(Map<String, dynamic> json) {
    final userId = _string(json['user_id']);
    if (userId == null || userId.isEmpty) return null;
    return PeerPresence(
      userId: userId,
      username: _string(json['username']) ?? '',
      displayName: _string(json['display_name']) ?? '',
      relativePath: _nonEmpty(json['path']),
      documentId: _nonEmpty(json['document_id']),
      blockId: _nonEmpty(json['block_id']),
      cursor: _nonEmpty(json['cursor']),
      selectionAnchor: _nonEmpty(json['selection_anchor']),
      idle: json['idle'] == true,
      updatedAt:
          DateTime.tryParse(_string(json['updated_at']) ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static String? _string(Object? value) => value is String ? value : null;

  static String? _nonEmpty(Object? value) {
    final text = _string(value);
    return text == null || text.isEmpty ? null : text;
  }

  PeerPresence copyWith({
    String? Function()? relativePath,
    String? Function()? documentId,
    String? Function()? blockId,
    String? Function()? cursor,
    String? Function()? selectionAnchor,
    bool? idle,
    DateTime? updatedAt,
  }) => PeerPresence(
    userId: userId,
    username: username,
    displayName: displayName,
    relativePath: relativePath == null ? this.relativePath : relativePath(),
    documentId: documentId == null ? this.documentId : documentId(),
    blockId: blockId == null ? this.blockId : blockId(),
    cursor: cursor == null ? this.cursor : cursor(),
    selectionAnchor:
        selectionAnchor == null ? this.selectionAnchor : selectionAnchor(),
    idle: idle ?? this.idle,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// True when the two describe the same position. Deliberately ignores
  /// [updatedAt]: it is what lets the sender skip a broadcast that would say
  /// nothing new, which matters because the editor republishes its focus on
  /// every keystroke.
  bool samePositionAs(PeerPresence other) =>
      userId == other.userId &&
      username == other.username &&
      displayName == other.displayName &&
      relativePath == other.relativePath &&
      documentId == other.documentId &&
      blockId == other.blockId &&
      cursor == other.cursor &&
      selectionAnchor == other.selectionAnchor &&
      idle == other.idle;

  @override
  bool operator ==(Object other) =>
      other is PeerPresence &&
      samePositionAs(other) &&
      updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
    userId,
    username,
    displayName,
    relativePath,
    documentId,
    blockId,
    cursor,
    selectionAnchor,
    idle,
    updatedAt,
  );

  @override
  String toString() =>
      'PeerPresence($userId at ${relativePath ?? '-'}#${blockId ?? '-'})';
}

/// Folds Realtime's raw presence state into one entry per person.
///
/// Pure on purpose. The controller around it cannot be tested without a live
/// socket, so everything that can be decided from the payloads alone is
/// decided here instead.
///
/// [selfUserId] is dropped: you are not your own collaborator. Somebody with
/// two windows open appears once, at whichever position they touched last.
Map<String, PeerPresence> peersFromPresencePayloads(
  Iterable<Iterable<Map<String, dynamic>>> payloadsByKey, {
  required String selfUserId,
}) {
  final peers = <String, PeerPresence>{};
  for (final payloads in payloadsByKey) {
    for (final payload in payloads) {
      final peer = PeerPresence.fromJson(payload);
      if (peer == null || peer.userId == selfUserId) continue;
      final existing = peers[peer.userId];
      if (existing == null || !peer.updatedAt.isBefore(existing.updatedAt)) {
        peers[peer.userId] = peer;
      }
    }
  }
  return peers;
}

/// Groups peers by the document they are in, dropping those in none.
Map<String, List<PeerPresence>> peersByPath(Iterable<PeerPresence> peers) {
  final byPath = <String, List<PeerPresence>>{};
  for (final peer in _ordered(peers)) {
    final path = peer.relativePath;
    if (path == null) continue;
    (byPath[path] ??= []).add(peer);
  }
  return byPath;
}

/// Groups the peers inside one document by the block they are in.
///
/// A peer whose block id is not in [knownBlockIds] is left out: the two copies
/// can hold different blocks for the same document while a proposal is
/// pending, and drawing a marker against a block you do not have would be a
/// guess. They still count in the document-level indicator.
Map<String, List<PeerPresence>> peersByBlock(
  Iterable<PeerPresence> peers, {
  required String relativePath,
  required Set<String> knownBlockIds,
}) {
  final byBlock = <String, List<PeerPresence>>{};
  for (final peer in _ordered(peers)) {
    final blockId = peer.blockId;
    if (peer.relativePath != relativePath || blockId == null) continue;
    if (!knownBlockIds.contains(blockId)) continue;
    (byBlock[blockId] ??= []).add(peer);
  }
  return byBlock;
}

/// A stable order, so a rebuild does not shuffle the dots. Sorting by user id
/// rather than by name keeps it steady while somebody is renaming themselves.
List<PeerPresence> _ordered(Iterable<PeerPresence> peers) =>
    peers.toList(growable: false)..sort((a, b) => a.userId.compareTo(b.userId));

/// Which colour a person gets, as an index into the presence palette.
///
/// Derived from the user id so the same person is the same colour on both
/// machines, and stays that colour between sessions.
int presenceColorIndex(String userId, int paletteLength) {
  assert(paletteLength > 0);
  var hash = 0;
  for (final unit in userId.codeUnits) {
    hash = (hash * 31 + unit) & 0x1FFFFFFF;
  }
  return hash % paletteLength;
}
