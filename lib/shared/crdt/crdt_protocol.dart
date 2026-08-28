/// DaySeven relay protocol v1.
///
/// Every WebSocket message is binary and has this layout:
///
///     version:u8 | opcode:u8 | metadataLength:u32be | metadata:utf8-json | body
///
/// The relay authenticates the socket and replaces `senderId` and
/// `senderRole` before forwarding a frame. Clients therefore never trust a
/// sender identity that originated in another client payload.
library;

import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

const int kCrdtProtocolVersion = 1;
const int kCrdtEnvelopeHeaderBytes = 6;
const int kMaxCrdtMetadataBytes = 16 * 1024;
const int kMaxStateVectorBytes = 64 * 1024;
const int kMaxChunkPayloadBytes = 128 * 1024;
const int kMaxChunkCount = 400;
const int kMaxAssembledBytes = 50 * 1024 * 1024;
const int kMaxProposalInventoryIds = 256;
const int kMaxMessageIdBytes = 128;
const int kMaxPendingAssemblies = 4;
const Duration kAssemblyTimeout = Duration(seconds: 30);
const int kReplayWindow = 512;

/// Opcodes are part of the server contract. Do not renumber them.
enum CrdtOpcode {
  peerJoined(0x01),
  peerLeft(0x02),
  stateVectorRequest(0x03),
  crdtUpdate(0x04),
  proposalInventory(0x05),
  proposalRequest(0x06),
  proposalData(0x07),
  proposalResolution(0x08),
  presence(0x09),
  ack(0x0a),
  error(0x0b);

  const CrdtOpcode(this.wire);
  final int wire;

  static CrdtOpcode? fromWire(int value) {
    for (final opcode in values) {
      if (opcode.wire == value) return opcode;
    }
    return null;
  }
}

class CrdtEnvelope {
  CrdtEnvelope({
    required this.opcode,
    required Map<String, Object?> metadata,
    Uint8List? body,
  }) : metadata = Map.unmodifiable(metadata),
       body = body ?? Uint8List(0);

  final CrdtOpcode opcode;
  final Map<String, Object?> metadata;
  final Uint8List body;

  String? get messageId =>
      metadata['messageId'] is String ? metadata['messageId']! as String : null;
  String? get senderId =>
      metadata['senderId'] is String ? metadata['senderId']! as String : null;
  String? get senderRole => metadata['senderRole'] is String
      ? metadata['senderRole']! as String
      : null;
}

enum CrdtRejection {
  wrongFrameType,
  wrongVersion,
  unknownOpcode,
  malformed,
  tooLarge,
  replay,
  incoherentChunking,
}

class CrdtProtocolException implements Exception {
  const CrdtProtocolException(this.rejection, this.message);
  final CrdtRejection rejection;
  final String message;

  @override
  String toString() => message;
}

Uint8List encodeEnvelope(CrdtEnvelope envelope) {
  final messageId = envelope.messageId;
  if (messageId == null || !_validMessageId(messageId)) {
    throw const CrdtProtocolException(
      CrdtRejection.malformed,
      'messageId is required and must be at most 128 UTF-8 bytes.',
    );
  }
  _validateTypedEnvelope(envelope, outbound: true);

  final metadataBytes = utf8.encode(jsonEncode(envelope.metadata));
  if (metadataBytes.length > kMaxCrdtMetadataBytes) {
    throw const CrdtProtocolException(
      CrdtRejection.tooLarge,
      'CRDT metadata exceeds 16 KiB.',
    );
  }
  final output = Uint8List(
    kCrdtEnvelopeHeaderBytes + metadataBytes.length + envelope.body.length,
  );
  final header = ByteData.sublistView(output);
  header.setUint8(0, kCrdtProtocolVersion);
  header.setUint8(1, envelope.opcode.wire);
  header.setUint32(2, metadataBytes.length, Endian.big);
  output.setRange(
    kCrdtEnvelopeHeaderBytes,
    kCrdtEnvelopeHeaderBytes + metadataBytes.length,
    metadataBytes,
  );
  output.setRange(
    kCrdtEnvelopeHeaderBytes + metadataBytes.length,
    output.length,
    envelope.body,
  );
  return output;
}

CrdtEnvelope decodeEnvelope(Object? raw) {
  if (raw is! List<int>) {
    throw const CrdtProtocolException(
      CrdtRejection.wrongFrameType,
      'The CRDT relay accepts binary WebSocket frames only.',
    );
  }
  if (raw.length < kCrdtEnvelopeHeaderBytes) {
    throw const CrdtProtocolException(
      CrdtRejection.malformed,
      'CRDT frame is shorter than its header.',
    );
  }
  final bytes = raw is Uint8List ? raw : Uint8List.fromList(raw);
  final header = ByteData.sublistView(bytes);
  if (header.getUint8(0) != kCrdtProtocolVersion) {
    throw const CrdtProtocolException(
      CrdtRejection.wrongVersion,
      'Unsupported CRDT relay protocol version.',
    );
  }
  final opcode = CrdtOpcode.fromWire(header.getUint8(1));
  if (opcode == null) {
    throw const CrdtProtocolException(
      CrdtRejection.unknownOpcode,
      'Unknown CRDT relay opcode.',
    );
  }
  final metadataLength = header.getUint32(2, Endian.big);
  if (metadataLength > kMaxCrdtMetadataBytes) {
    throw const CrdtProtocolException(
      CrdtRejection.tooLarge,
      'CRDT metadata exceeds 16 KiB.',
    );
  }
  final metadataEnd = kCrdtEnvelopeHeaderBytes + metadataLength;
  if (metadataEnd > bytes.length) {
    throw const CrdtProtocolException(
      CrdtRejection.malformed,
      'CRDT metadata length exceeds the frame.',
    );
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(
      utf8.decode(bytes.sublist(kCrdtEnvelopeHeaderBytes, metadataEnd)),
    );
  } on Object {
    throw const CrdtProtocolException(
      CrdtRejection.malformed,
      'CRDT metadata is not UTF-8 JSON.',
    );
  }
  if (decoded is! Map) {
    throw const CrdtProtocolException(
      CrdtRejection.malformed,
      'CRDT metadata must be a JSON object.',
    );
  }
  final metadata = <String, Object?>{};
  for (final entry in decoded.entries) {
    if (entry.key is! String) {
      throw const CrdtProtocolException(
        CrdtRejection.malformed,
        'CRDT metadata keys must be strings.',
      );
    }
    metadata[entry.key as String] = entry.value;
  }
  final envelope = CrdtEnvelope(
    opcode: opcode,
    metadata: metadata,
    body: Uint8List.sublistView(bytes, metadataEnd),
  );
  final messageId = envelope.messageId;
  if (messageId == null || !_validMessageId(messageId)) {
    throw const CrdtProtocolException(
      CrdtRejection.malformed,
      'messageId is required and must be at most 128 UTF-8 bytes.',
    );
  }
  _validateTypedEnvelope(envelope, outbound: false);
  return envelope;
}

/// Encodes one logical message into relay-sized binary frames.
///
/// Only CRDT updates and proposal data may be chunked. They always carry the
/// chunk fields, including when the body fits in a single frame.
List<Uint8List> encodeChunkedEnvelopes({
  required CrdtOpcode opcode,
  required String messageId,
  required Map<String, Object?> metadata,
  required List<int> body,
  int maxChunkBytes = kMaxChunkPayloadBytes,
}) {
  if (opcode != CrdtOpcode.crdtUpdate && opcode != CrdtOpcode.proposalData) {
    throw ArgumentError.value(opcode, 'opcode', 'is not chunkable');
  }
  if (maxChunkBytes < 1 || maxChunkBytes > kMaxChunkPayloadBytes) {
    throw RangeError.range(
      maxChunkBytes,
      1,
      kMaxChunkPayloadBytes,
      'maxChunkBytes',
    );
  }
  if (body.length > kMaxAssembledBytes) {
    throw const CrdtProtocolException(
      CrdtRejection.tooLarge,
      'CRDT message exceeds the 50 MiB workspace ceiling.',
    );
  }
  final count = body.isEmpty
      ? 1
      : (body.length + maxChunkBytes - 1) ~/ maxChunkBytes;
  if (count > kMaxChunkCount) {
    throw const CrdtProtocolException(
      CrdtRejection.tooLarge,
      'CRDT message requires too many chunks.',
    );
  }
  return [
    for (var index = 0; index < count; index++)
      encodeEnvelope(
        CrdtEnvelope(
          opcode: opcode,
          metadata: {
            ...metadata,
            'messageId': messageId,
            'chunkIndex': index,
            'chunkCount': count,
            'totalBytes': body.length,
          },
          body: Uint8List.fromList(
            body.sublist(
              index * maxChunkBytes,
              ((index + 1) * maxChunkBytes).clamp(0, body.length),
            ),
          ),
        ),
      ),
  ];
}

class CrdtAssemblyResult {
  const CrdtAssemblyResult.message(this.message) : rejection = null;
  const CrdtAssemblyResult.incomplete() : message = null, rejection = null;
  const CrdtAssemblyResult.rejected(this.rejection) : message = null;

  final CrdtEnvelope? message;
  final CrdtRejection? rejection;
  bool get isMessage => message != null;
  bool get isIncomplete => message == null && rejection == null;
  bool get isRejected => rejection != null;
}

/// Bounded chunk reassembly and replay rejection for inbound relay frames.
class CrdtAssembler {
  CrdtAssembler({
    this.maxPendingAssemblies = kMaxPendingAssemblies,
    this.assemblyTimeout = kAssemblyTimeout,
    this.replayWindow = kReplayWindow,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final int maxPendingAssemblies;
  final Duration assemblyTimeout;
  final int replayWindow;
  final DateTime Function() _now;
  final Map<String, _Assembly> _pending = {};
  final Queue<String> _seen = Queue<String>();
  final Set<String> _seenIndex = {};

  int get pendingCount => _pending.length;

  CrdtAssemblyResult accept(Object? raw) {
    final CrdtEnvelope frame;
    try {
      frame = decodeEnvelope(raw);
    } on CrdtProtocolException catch (error) {
      return CrdtAssemblyResult.rejected(error.rejection);
    }
    final sender = frame.senderId ?? 'relay';
    final messageId = frame.messageId!;
    final key = '$sender/$messageId';
    if (_seenIndex.contains(key)) {
      return const CrdtAssemblyResult.rejected(CrdtRejection.replay);
    }

    if (frame.opcode != CrdtOpcode.crdtUpdate &&
        frame.opcode != CrdtOpcode.proposalData) {
      _remember(key);
      return CrdtAssemblyResult.message(frame);
    }

    _expire();
    final index = frame.metadata['chunkIndex'] as int;
    final count = frame.metadata['chunkCount'] as int;
    final totalBytes = frame.metadata['totalBytes'] as int;
    if (count == 1) {
      _remember(key);
      return CrdtAssemblyResult.message(frame);
    }

    final assembly = _pending.putIfAbsent(
      key,
      () => _Assembly(
        opcode: frame.opcode,
        count: count,
        totalBytes: totalBytes,
        metadata: frame.metadata,
        startedAt: _now(),
      ),
    );
    if (assembly.opcode != frame.opcode ||
        assembly.count != count ||
        assembly.totalBytes != totalBytes) {
      _pending.remove(key);
      return const CrdtAssemblyResult.rejected(
        CrdtRejection.incoherentChunking,
      );
    }
    final previous = assembly.chunks[index];
    if (previous != null) {
      if (!_sameBytes(previous, frame.body)) {
        _pending.remove(key);
        return const CrdtAssemblyResult.rejected(
          CrdtRejection.incoherentChunking,
        );
      }
      return const CrdtAssemblyResult.incomplete();
    }
    if (assembly.byteCount + frame.body.length > totalBytes) {
      _pending.remove(key);
      return const CrdtAssemblyResult.rejected(CrdtRejection.tooLarge);
    }
    assembly.chunks[index] = frame.body;
    assembly.byteCount += frame.body.length;

    while (_pending.length > maxPendingAssemblies) {
      _pending.remove(_pending.keys.first);
    }
    if (assembly.chunks.length != count) {
      return const CrdtAssemblyResult.incomplete();
    }
    if (assembly.byteCount != totalBytes) {
      _pending.remove(key);
      return const CrdtAssemblyResult.rejected(
        CrdtRejection.incoherentChunking,
      );
    }

    final joined = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      final chunk = assembly.chunks[i];
      if (chunk == null) return const CrdtAssemblyResult.incomplete();
      joined.add(chunk);
    }
    _pending.remove(key);
    _remember(key);
    final metadata = Map<String, Object?>.from(assembly.metadata)
      ..remove('chunkIndex')
      ..remove('chunkCount')
      ..remove('totalBytes');
    return CrdtAssemblyResult.message(
      CrdtEnvelope(
        opcode: frame.opcode,
        metadata: metadata,
        body: joined.takeBytes(),
      ),
    );
  }

  void _expire() {
    final cutoff = _now().subtract(assemblyTimeout);
    _pending.removeWhere((_, assembly) => assembly.startedAt.isBefore(cutoff));
  }

  void _remember(String key) {
    _seen.addLast(key);
    _seenIndex.add(key);
    while (_seen.length > replayWindow) {
      _seenIndex.remove(_seen.removeFirst());
    }
  }
}

void _validateTypedEnvelope(CrdtEnvelope envelope, {required bool outbound}) {
  final metadata = envelope.metadata;
  final body = envelope.body;
  int? integer(String key) =>
      metadata[key] is int ? metadata[key]! as int : null;
  String? string(String key) =>
      metadata[key] is String ? metadata[key]! as String : null;

  switch (envelope.opcode) {
    case CrdtOpcode.peerJoined:
    case CrdtOpcode.peerLeft:
    case CrdtOpcode.error:
      if (outbound) {
        throw CrdtProtocolException(
          CrdtRejection.malformed,
          '${envelope.opcode.name} is server-generated.',
        );
      }
    case CrdtOpcode.stateVectorRequest:
      if (body.length > kMaxStateVectorBytes) {
        throw const CrdtProtocolException(
          CrdtRejection.tooLarge,
          'State vector exceeds 64 KiB.',
        );
      }
    case CrdtOpcode.crdtUpdate:
    case CrdtOpcode.proposalData:
      final index = integer('chunkIndex');
      final count = integer('chunkCount');
      final total = integer('totalBytes');
      if (index == null ||
          count == null ||
          total == null ||
          index < 0 ||
          count < 1 ||
          count > kMaxChunkCount ||
          index >= count ||
          total < 0 ||
          total > kMaxAssembledBytes) {
        throw const CrdtProtocolException(
          CrdtRejection.incoherentChunking,
          'Invalid CRDT chunk metadata.',
        );
      }
      if (body.length > kMaxChunkPayloadBytes || body.length > total) {
        throw const CrdtProtocolException(
          CrdtRejection.tooLarge,
          'CRDT chunk exceeds its declared bounds.',
        );
      }
      if (envelope.opcode == CrdtOpcode.proposalData &&
          !_validIdentifier(string('proposalId'))) {
        throw const CrdtProtocolException(
          CrdtRejection.malformed,
          'proposal-data requires proposalId.',
        );
      }
    case CrdtOpcode.proposalInventory:
      final ids = metadata['proposalIds'];
      if (ids is! List ||
          ids.length > kMaxProposalInventoryIds ||
          ids.any((id) => id is! String || !_validIdentifier(id))) {
        throw const CrdtProtocolException(
          CrdtRejection.malformed,
          'proposal-inventory requires up to 256 proposal IDs.',
        );
      }
      if (body.isNotEmpty) _mustBeEmpty();
    case CrdtOpcode.proposalRequest:
      if (!_validIdentifier(string('proposalId')) || body.isNotEmpty) {
        throw const CrdtProtocolException(
          CrdtRejection.malformed,
          'proposal-request requires proposalId and an empty body.',
        );
      }
    case CrdtOpcode.proposalResolution:
      final status = string('status');
      final note = string('note');
      if (!_validIdentifier(string('proposalId')) ||
          (status != 'approved' && status != 'rejected') ||
          (note != null && utf8.encode(note).length > 2048) ||
          body.isNotEmpty) {
        throw const CrdtProtocolException(
          CrdtRejection.malformed,
          'Invalid proposal resolution.',
        );
      }
    case CrdtOpcode.presence:
      if (body.length > kMaxCrdtMetadataBytes) {
        throw const CrdtProtocolException(
          CrdtRejection.tooLarge,
          'Presence exceeds 16 KiB.',
        );
      }
      try {
        jsonDecode(utf8.decode(body));
      } on Object {
        throw const CrdtProtocolException(
          CrdtRejection.malformed,
          'Presence body must be UTF-8 JSON.',
        );
      }
    case CrdtOpcode.ack:
      if (!_validIdentifier(string('ackedMessageId')) || body.isNotEmpty) {
        throw const CrdtProtocolException(
          CrdtRejection.malformed,
          'ack requires ackedMessageId and an empty body.',
        );
      }
  }
}

Never _mustBeEmpty() => throw const CrdtProtocolException(
  CrdtRejection.malformed,
  'This CRDT message requires an empty body.',
);

bool _validMessageId(String value) =>
    value.isNotEmpty && utf8.encode(value).length <= kMaxMessageIdBytes;

bool _validIdentifier(String? value) =>
    value != null && value.isNotEmpty && utf8.encode(value).length <= 256;

bool _sameBytes(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

class _Assembly {
  _Assembly({
    required this.opcode,
    required this.count,
    required this.totalBytes,
    required this.metadata,
    required this.startedAt,
  });

  final CrdtOpcode opcode;
  final int count;
  final int totalBytes;
  final Map<String, Object?> metadata;
  final DateTime startedAt;
  final Map<int, Uint8List> chunks = {};
  int byteCount = 0;
}
