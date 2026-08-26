/// The wire protocol for `crdt:<kbId>`, and the rules for not trusting it.
///
/// Everything arriving on this topic was written by another client. Realtime
/// authenticates the sender and RLS proves they are a member with an editing
/// role, and that is the entire extent of what is known about a message. The
/// bytes inside are unverified, may be malformed, may be enormous, may be a
/// replay, and may be a deliberate attempt to exhaust this process.
///
/// So the shape here is deliberately narrow:
///
///   * a **closed set** of message types — anything else is dropped unread;
///   * payloads that are **file UUIDs and opaque CRDT bytes only** — never a
///     path, a command, a URL, or anything that gets interpreted;
///   * a **size limit checked before decoding**, not after;
///   * **chunking**, because Realtime caps a payload at 256 KB and a first
///     sync of a real Knowledge Base is larger than that;
///   * **replay rejection**, because a resent chunk from a hostile or merely
///     confused peer must not be able to reassemble into something new.
///
/// Nothing in this file evaluates, deserialises into a class by name, resolves
/// a path, or performs I/O. It turns bytes into either a `CrdtMessage` or
/// nothing at all.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

/// Realtime's hard ceiling for one broadcast payload.
const int kMaxRealtimePayloadBytes = 256 * 1024;

/// Raw bytes per chunk before base64, which adds about a third. 128 KB encodes
/// to ~171 KB, leaving room for the JSON envelope inside the 256 KB ceiling.
const int kMaxChunkPayloadBytes = 128 * 1024;

/// The largest reassembled update this peer will build. A first sync of a big
/// Knowledge Base is legitimately megabytes; anything past this is a peer
/// trying to make us allocate.
const int kMaxAssembledBytes = 8 * 1024 * 1024;

/// A single non-chunked update. Matches the server's `yjs_max_update_bytes`.
const int kMaxSingleUpdateBytes = 1024 * 1024;

/// Control messages carry identifiers, never content, so they are small. A
/// large one is a malformed or hostile one.
const int kMaxControlPayloadBytes = 16 * 1024;

/// How many partially-received chunk sets to hold at once. Past this the
/// oldest is dropped: a peer that starts many assemblies and finishes none is
/// otherwise an unbounded memory cost.
const int kMaxPendingAssemblies = 4;

/// An assembly that has not completed in this long is abandoned. The durable
/// log makes anything lost recoverable, so waiting longer buys nothing.
const Duration kAssemblyTimeout = Duration(seconds: 30);

/// How many recently-seen message ids to remember for replay rejection.
const int kReplayWindow = 512;

/// The closed set. A message whose type is not one of these is dropped without
/// being decoded — that is the point of an allowlist rather than a blocklist.
enum CrdtMessageType {
  /// "Here is my state vector; send me what I am missing."
  syncStep1('sync-step-1'),

  /// The reply to [syncStep1]: everything the asker lacked.
  syncStep2('sync-step-2'),

  /// An incremental update from a peer's ongoing editing.
  crdtUpdate('crdt-update'),

  /// Cursor, selection and active file. Ephemeral.
  awareness('awareness'),

  ping('ping'),
  pong('pong'),

  /// A change to a protected file, which cannot be applied directly and
  /// travels as a reviewable proposal instead.
  proposalUpdate('proposal-update');

  const CrdtMessageType(this.wire);

  /// The value that actually crosses the wire. Kept separate from the Dart
  /// name so renaming the enum cannot silently break compatibility with a
  /// build already in the field.
  final String wire;

  static CrdtMessageType? fromWire(Object? value) {
    if (value is! String) return null;
    for (final type in CrdtMessageType.values) {
      if (type.wire == value) return type;
    }
    return null;
  }
}

/// One decoded, size-checked, non-replayed message.
class CrdtMessage {
  const CrdtMessage({
    required this.type,
    required this.messageId,
    required this.senderId,
    required this.payload,
  });

  final CrdtMessageType type;

  /// Unique per message per sender. Used to reject replays, and to group the
  /// chunks of one logical message.
  final String messageId;

  final String senderId;

  /// Opaque to this layer: CRDT bytes for the sync types, UTF-8 JSON for
  /// awareness. Never a path or a command.
  final Uint8List payload;

  int get byteSize => payload.length;
}

/// A message being sent, already split into wire-sized frames.
class CrdtFrame {
  const CrdtFrame(this.payload);

  /// Ready to hand to `sendBroadcastMessage`.
  final Map<String, Object?> payload;
}

/// Splits an outbound message into frames that fit Realtime's ceiling.
///
/// A message small enough to travel whole still gets a chunk envelope, so the
/// receiver has exactly one code path and a single-frame message is not a
/// special case that only gets tested by accident.
List<CrdtFrame> encodeMessage({
  required CrdtMessageType type,
  required String messageId,
  required String senderId,
  required List<int> payload,
  int maxChunkBytes = kMaxChunkPayloadBytes,
}) {
  assert(maxChunkBytes > 0);
  final total = payload.isEmpty
      ? 1
      : (payload.length + maxChunkBytes - 1) ~/ maxChunkBytes;
  return [
    for (var index = 0; index < total; index++)
      CrdtFrame({
        't': type.wire,
        'mid': messageId,
        'sender': senderId,
        'i': index,
        'n': total,
        'b': base64Encode(
          payload.sublist(
            index * maxChunkBytes,
            ((index + 1) * maxChunkBytes).clamp(0, payload.length),
          ),
        ),
      }),
  ];
}

/// Why a frame was dropped. Surfaced so phase 10 can log it: a peer producing
/// these steadily is doing something worth knowing about.
enum CrdtRejection {
  unknownType,
  malformed,
  tooLarge,
  replay,
  incoherentChunking,
  assemblyAbandoned,
}

/// A frame is one of exactly three things, and callers must handle all three:
/// it completed a message, it was refused, or it was a valid chunk of
/// something still arriving. Collapsing the third into either of the others is
/// how a chunked message ends up logged as an attack or applied half-formed.
class CrdtDecodeResult {
  const CrdtDecodeResult.message(this.message)
    : rejection = null,
      senderId = null;
  const CrdtDecodeResult.rejected(this.rejection, {this.senderId})
    : message = null;
  const CrdtDecodeResult.incomplete({this.senderId})
    : message = null,
      rejection = null;

  /// Non-null only when a complete message was assembled.
  final CrdtMessage? message;

  /// Non-null when the frame was refused.
  final CrdtRejection? rejection;

  /// Best-effort attribution, for logging. Null when the frame was too
  /// malformed to name a sender.
  final String? senderId;

  bool get isMessage => message != null;
  bool get isRejected => rejection != null;

  /// A well-formed chunk of a message that is still arriving.
  bool get isIncomplete => message == null && rejection == null;
}

/// Reassembles inbound frames, refusing anything that does not add up.
///
/// One of these per session. It is deliberately stateful and deliberately
/// bounded: every collection inside has a cap, because the whole point is to
/// survive a peer that does not stop.
class CrdtAssembler {
  CrdtAssembler({
    this.maxAssembledBytes = kMaxAssembledBytes,
    this.maxPendingAssemblies = kMaxPendingAssemblies,
    this.assemblyTimeout = kAssemblyTimeout,
    this.replayWindow = kReplayWindow,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final int maxAssembledBytes;
  final int maxPendingAssemblies;
  final Duration assemblyTimeout;
  final int replayWindow;
  final DateTime Function() _now;

  /// Keyed by "sender/messageId" so two peers cannot collide, and a peer
  /// cannot displace another's assembly by guessing an id.
  final Map<String, _Assembly> _pending = <String, _Assembly>{};

  /// Insertion-ordered, so eviction is oldest-first without a sort.
  final Queue<String> _seen = Queue<String>();
  final Set<String> _seenIndex = <String>{};

  int get pendingCount => _pending.length;

  /// Takes one raw broadcast payload and returns either a whole message or a
  /// reason it was refused.
  CrdtDecodeResult accept(Map<String, dynamic> raw) {
    final type = CrdtMessageType.fromWire(raw['t']);
    final sender = _string(raw['sender']);
    if (type == null) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.unknownType,
        senderId: sender,
      );
    }

    final messageId = _string(raw['mid']);
    final index = _int(raw['i']);
    final total = _int(raw['n']);
    final encoded = _string(raw['b']);
    if (messageId == null ||
        messageId.isEmpty ||
        sender == null ||
        sender.isEmpty ||
        index == null ||
        total == null ||
        encoded == null) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.malformed,
        senderId: sender,
      );
    }
    if (total < 1 || index < 0 || index >= total) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.incoherentChunking,
        senderId: sender,
      );
    }

    // Refuse on the encoded length, before allocating the decoded bytes. A
    // base64 string is 4/3 of what it decodes to, so this is the cheap check
    // that makes the expensive one safe.
    if (encoded.length > kMaxRealtimePayloadBytes) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.tooLarge,
        senderId: sender,
      );
    }
    if (total * kMaxChunkPayloadBytes > maxAssembledBytes) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.tooLarge,
        senderId: sender,
      );
    }

    final Uint8List bytes;
    try {
      bytes = base64Decode(encoded);
    } on FormatException {
      return CrdtDecodeResult.rejected(
        CrdtRejection.malformed,
        senderId: sender,
      );
    }
    if (bytes.length > kMaxChunkPayloadBytes) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.tooLarge,
        senderId: sender,
      );
    }
    if (_isControl(type) && bytes.length > kMaxControlPayloadBytes) {
      return CrdtDecodeResult.rejected(
        CrdtRejection.tooLarge,
        senderId: sender,
      );
    }

    final key = '$sender/$messageId';
    if (_seenIndex.contains(key)) {
      return CrdtDecodeResult.rejected(CrdtRejection.replay, senderId: sender);
    }

    // The single-frame case completes without ever entering _pending, so the
    // common path costs no bookkeeping.
    if (total == 1) {
      _remember(key);
      return CrdtDecodeResult.message(
        CrdtMessage(
          type: type,
          messageId: messageId,
          senderId: sender,
          payload: bytes,
        ),
      );
    }

    _expire();
    final assembly = _pending.putIfAbsent(
      key,
      () => _Assembly(type: type, total: total, startedAt: _now()),
    );
    // A sender that changes the type or length of a message mid-assembly is
    // not one to keep reassembling for.
    if (assembly.type != type || assembly.total != total) {
      _pending.remove(key);
      return CrdtDecodeResult.rejected(
        CrdtRejection.incoherentChunking,
        senderId: sender,
      );
    }
    if (assembly.chunks.containsKey(index)) {
      return CrdtDecodeResult.rejected(CrdtRejection.replay, senderId: sender);
    }
    if (assembly.byteCount + bytes.length > maxAssembledBytes) {
      _pending.remove(key);
      return CrdtDecodeResult.rejected(
        CrdtRejection.tooLarge,
        senderId: sender,
      );
    }
    assembly.chunks[index] = bytes;
    assembly.byteCount += bytes.length;

    if (_pending.length > maxPendingAssemblies) {
      _pending.remove(_pending.keys.first);
    }
    if (assembly.chunks.length < total) {
      return CrdtDecodeResult.incomplete(senderId: sender);
    }

    _pending.remove(key);
    _remember(key);
    final joined = BytesBuilder(copy: false);
    for (var i = 0; i < total; i++) {
      joined.add(assembly.chunks[i]!);
    }
    return CrdtDecodeResult.message(
      CrdtMessage(
        type: type,
        messageId: messageId,
        senderId: sender,
        payload: joined.takeBytes(),
      ),
    );
  }

  /// Drops assemblies that have been open too long.
  void _expire() {
    if (_pending.isEmpty) return;
    final cutoff = _now().subtract(assemblyTimeout);
    _pending.removeWhere((_, a) => a.startedAt.isBefore(cutoff));
  }

  void _remember(String key) {
    _seen.addLast(key);
    _seenIndex.add(key);
    while (_seen.length > replayWindow) {
      _seenIndex.remove(_seen.removeFirst());
    }
  }

  static bool _isControl(CrdtMessageType type) => switch (type) {
    CrdtMessageType.awareness ||
    CrdtMessageType.ping ||
    CrdtMessageType.pong ||
    CrdtMessageType.syncStep1 => true,
    CrdtMessageType.syncStep2 ||
    CrdtMessageType.crdtUpdate ||
    CrdtMessageType.proposalUpdate => false,
  };

  static String? _string(Object? value) => value is String ? value : null;

  static int? _int(Object? value) => value is int
      ? value
      : value is num
      ? value.toInt()
      : null;
}

class _Assembly {
  _Assembly({required this.type, required this.total, required this.startedAt});

  final CrdtMessageType type;
  final int total;
  final DateTime startedAt;
  final Map<int, Uint8List> chunks = <int, Uint8List>{};
  int byteCount = 0;
}
