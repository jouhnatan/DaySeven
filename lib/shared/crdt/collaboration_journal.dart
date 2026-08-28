/// Device-local durable collaboration state.
///
/// The journal is never synchronized as a SQLite file. Proposal records and
/// outbox entries are serialized into typed relay messages, while
/// `workspace.bin` remains the canonical local CRDT document.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:dayseven/shared/kb/bundle.dart';

const String kCollaborationJournalName = 'collaboration.sqlite';
const int kCollaborationJournalSchemaVersion = 1;
const int kProposalPayloadVersion = 1;

enum CollaborationProposalStatus {
  pending,
  approved,
  rejected;

  static CollaborationProposalStatus fromWire(String value) => switch (value) {
    'pending' => pending,
    'approved' => approved,
    'rejected' => rejected,
    _ => throw FormatException('Unknown proposal status: $value'),
  };
}

enum CollaborationResolutionStatus {
  approved,
  rejected;

  static CollaborationResolutionStatus fromWire(String value) =>
      switch (value) {
        'approved' => approved,
        'rejected' => rejected,
        _ => throw FormatException('Unknown resolution status: $value'),
      };
}

class CollaborationProposal {
  CollaborationProposal({
    required this.proposalId,
    required this.fileId,
    required this.authorId,
    required Uint8List baseSnapshot,
    required Uint8List update,
    required this.createdAt,
    this.status = CollaborationProposalStatus.pending,
    this.reviewNote,
    this.resolvedBy,
    this.resolvedAt,
  }) : baseSnapshot = Uint8List.fromList(baseSnapshot),
       update = Uint8List.fromList(update);

  final String proposalId;
  final String fileId;
  final String authorId;
  final Uint8List baseSnapshot;
  final Uint8List update;
  final DateTime createdAt;
  final CollaborationProposalStatus status;
  final String? reviewNote;
  final String? resolvedBy;
  final DateTime? resolvedAt;
}

class CollaborationResolution {
  const CollaborationResolution({
    required this.proposalId,
    required this.status,
    required this.resolvedBy,
    required this.resolvedAt,
    this.note,
  });

  final String proposalId;
  final CollaborationResolutionStatus status;
  final String resolvedBy;
  final DateTime resolvedAt;
  final String? note;
}

class ResolutionWriteResult {
  const ResolutionWriteResult(this.resolution, {required this.accepted});
  final CollaborationResolution resolution;

  /// False when another resolution was already recorded. First resolution
  /// wins locally, matching the relay's serialized resolution behavior.
  final bool accepted;
}

class CollaborationOutboxEntry {
  CollaborationOutboxEntry({
    required this.id,
    required this.opcode,
    required Map<String, Object?> metadata,
    required Uint8List body,
    required this.createdAt,
    required this.attemptCount,
    this.messageId,
  }) : metadata = Map.unmodifiable(metadata),
       body = Uint8List.fromList(body);

  final int id;
  final CrdtOpcode opcode;
  final Map<String, Object?> metadata;
  final Uint8List body;
  final DateTime createdAt;
  final int attemptCount;
  final String? messageId;
}

class CollaborationJournal {
  CollaborationJournal._(this._db, this.path);

  final Database _db;
  final String path;
  bool _closed = false;

  static Future<CollaborationJournal> open({required String rootPath}) async {
    final directory = Directory(p.join(rootPath, kMetadataDirName, 'yjs'));
    await directory.create(recursive: true);
    final path = p.join(directory.path, kCollaborationJournalName);
    final db = sqlite3.open(path);
    try {
      db.execute('pragma foreign_keys = on;');
      db.execute('pragma journal_mode = wal;');
      db.execute('''
        create table if not exists proposals (
          proposal_id text primary key,
          file_id text not null,
          author_id text not null,
          base_snapshot blob not null,
          proposal_update blob not null,
          created_at_ms integer not null,
          status text not null check (status in ('pending', 'approved', 'rejected')),
          review_note text,
          resolved_by text,
          resolved_at_ms integer
        );
        create table if not exists proposal_resolutions (
          proposal_id text primary key references proposals(proposal_id),
          status text not null check (status in ('approved', 'rejected')),
          resolved_by text not null,
          note text,
          resolved_at_ms integer not null
        );
        create table if not exists outbox (
          id integer primary key autoincrement,
          opcode integer not null,
          metadata_json text not null,
          body blob not null,
          created_at_ms integer not null,
          attempt_count integer not null default 0,
          message_id text
        );
        create index if not exists proposals_status_created
          on proposals(status, created_at_ms);
        create index if not exists outbox_created on outbox(id);
        pragma user_version = $kCollaborationJournalSchemaVersion;
      ''');
      return CollaborationJournal._(db, path);
    } on Object {
      db.close();
      rethrow;
    }
  }

  void saveProposal(CollaborationProposal proposal) {
    _checkOpen();
    _db.execute(
      '''
      insert into proposals (
        proposal_id, file_id, author_id, base_snapshot, proposal_update,
        created_at_ms, status, review_note, resolved_by, resolved_at_ms
      ) values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      on conflict(proposal_id) do update set
        file_id = excluded.file_id,
        author_id = excluded.author_id,
        base_snapshot = excluded.base_snapshot,
        proposal_update = excluded.proposal_update
      where proposals.status = 'pending';
    ''',
      [
        proposal.proposalId,
        proposal.fileId,
        proposal.authorId,
        proposal.baseSnapshot,
        proposal.update,
        proposal.createdAt.toUtc().millisecondsSinceEpoch,
        proposal.status.name,
        proposal.reviewNote,
        proposal.resolvedBy,
        proposal.resolvedAt?.toUtc().millisecondsSinceEpoch,
      ],
    );
  }

  CollaborationProposal? proposal(String proposalId) {
    _checkOpen();
    final rows = _db.select(
      'select * from proposals where proposal_id = ? limit 1;',
      [proposalId],
    );
    return rows.isEmpty ? null : _proposalFromRow(rows.first);
  }

  List<CollaborationProposal> proposals({CollaborationProposalStatus? status}) {
    _checkOpen();
    final ResultSet rows;
    if (status == null) {
      rows = _db.select(
        'select * from proposals order by created_at_ms, proposal_id;',
      );
    } else {
      rows = _db.select(
        'select * from proposals where status = ? order by created_at_ms, proposal_id;',
        [status.name],
      );
    }
    return [for (final row in rows) _proposalFromRow(row)];
  }

  List<String> proposalIds() {
    _checkOpen();
    final rows = _db.select(
      'select proposal_id from proposals order by created_at_ms, proposal_id '
      'limit $kMaxProposalInventoryIds;',
    );
    return [for (final row in rows) row['proposal_id']! as String];
  }

  CollaborationResolution? resolution(String proposalId) {
    _checkOpen();
    final rows = _db.select(
      'select * from proposal_resolutions where proposal_id = ? limit 1;',
      [proposalId],
    );
    return rows.isEmpty ? null : _resolutionFromRow(rows.first);
  }

  List<CollaborationResolution> resolutions({int limit = 256}) {
    _checkOpen();
    final safeLimit = limit.clamp(1, 256);
    final rows = _db.select(
      'select * from proposal_resolutions order by resolved_at_ms, proposal_id '
      'limit $safeLimit;',
    );
    return [for (final row in rows) _resolutionFromRow(row)];
  }

  ResolutionWriteResult recordResolution(CollaborationResolution next) {
    _checkOpen();
    _db.execute('begin immediate;');
    try {
      final existing = resolution(next.proposalId);
      if (existing != null) {
        _db.execute('commit;');
        return ResolutionWriteResult(existing, accepted: false);
      }
      if (proposal(next.proposalId) == null) {
        throw StateError('Unknown proposal ${next.proposalId}.');
      }
      _db.execute(
        '''
        insert into proposal_resolutions (
          proposal_id, status, resolved_by, note, resolved_at_ms
        ) values (?, ?, ?, ?, ?);
      ''',
        [
          next.proposalId,
          next.status.name,
          next.resolvedBy,
          next.note,
          next.resolvedAt.toUtc().millisecondsSinceEpoch,
        ],
      );
      _db.execute(
        '''
        update proposals
        set status = ?, review_note = ?, resolved_by = ?, resolved_at_ms = ?
        where proposal_id = ? and status = 'pending';
      ''',
        [
          next.status.name,
          next.note,
          next.resolvedBy,
          next.resolvedAt.toUtc().millisecondsSinceEpoch,
          next.proposalId,
        ],
      );
      _db.execute('commit;');
      return ResolutionWriteResult(next, accepted: true);
    } on Object {
      _db.execute('rollback;');
      rethrow;
    }
  }

  int enqueue({
    required CrdtOpcode opcode,
    Map<String, Object?> metadata = const {},
    List<int> body = const [],
    DateTime? createdAt,
  }) {
    _checkOpen();
    final safeMetadata = Map<String, Object?>.from(metadata)
      ..remove('messageId')
      ..remove('senderId')
      ..remove('senderRole');
    _db.execute(
      '''
      insert into outbox (opcode, metadata_json, body, created_at_ms)
      values (?, ?, ?, ?);
    ''',
      [
        opcode.wire,
        jsonEncode(safeMetadata),
        Uint8List.fromList(body),
        (createdAt ?? DateTime.now()).toUtc().millisecondsSinceEpoch,
      ],
    );
    return _db.lastInsertRowId;
  }

  List<CollaborationOutboxEntry> pendingOutbox({int limit = 64}) {
    _checkOpen();
    final safeLimit = limit.clamp(1, 256);
    final rows = _db.select(
      'select * from outbox order by id limit $safeLimit;',
    );
    return [for (final row in rows) _outboxFromRow(row)];
  }

  /// Entries that are not already awaiting an acknowledgement. An entry keeps
  /// its [CollaborationOutboxEntry.id] in the outbox until the relay acks it,
  /// so transmitting on the strength of [pendingOutbox] alone re-sends every
  /// in-flight entry on each drain — and rewrites the message id the pending
  /// ack refers to.
  List<CollaborationOutboxEntry> sendableOutbox({int limit = 64}) {
    _checkOpen();
    final safeLimit = limit.clamp(1, 256);
    final rows = _db.select(
      'select * from outbox where message_id is null order by id limit $safeLimit;',
    );
    return [for (final row in rows) _outboxFromRow(row)];
  }

  /// Returns in-flight entries to the sendable set. A dropped socket loses any
  /// acknowledgement still in transit, so the next connection must resend them.
  void requeueInFlight() {
    _checkOpen();
    _db.execute('update outbox set message_id = null;');
  }

  void markAttempt(int id, String messageId) {
    _checkOpen();
    _db.execute(
      '''
      update outbox
      set attempt_count = attempt_count + 1, message_id = ?
      where id = ?;
    ''',
      [messageId, id],
    );
  }

  void acknowledge(String messageId) {
    _checkOpen();
    _db.execute('delete from outbox where message_id = ?;', [messageId]);
  }

  void removeOutbox(int id) {
    _checkOpen();
    _db.execute('delete from outbox where id = ?;', [id]);
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _db.close();
  }

  void _checkOpen() {
    if (_closed) throw StateError('CollaborationJournal is closed.');
  }
}

/// Proposal-data body. The server intentionally treats it as opaque.
Uint8List encodeProposalPayload(CollaborationProposal proposal) {
  final metadata = utf8.encode(
    jsonEncode({
      'fileId': proposal.fileId,
      'createdAt': proposal.createdAt.toUtc().toIso8601String(),
    }),
  );
  if (metadata.length > kMaxCrdtMetadataBytes ||
      proposal.baseSnapshot.length + proposal.update.length >
          kMaxAssembledBytes - metadata.length - 9) {
    throw const CrdtProtocolException(
      CrdtRejection.tooLarge,
      'Proposal payload exceeds collaboration limits.',
    );
  }
  final output = Uint8List(
    1 +
        4 +
        metadata.length +
        4 +
        proposal.baseSnapshot.length +
        proposal.update.length,
  );
  final data = ByteData.sublistView(output);
  data.setUint8(0, kProposalPayloadVersion);
  data.setUint32(1, metadata.length, Endian.big);
  var offset = 5;
  output.setRange(offset, offset + metadata.length, metadata);
  offset += metadata.length;
  data.setUint32(offset, proposal.baseSnapshot.length, Endian.big);
  offset += 4;
  output.setRange(
    offset,
    offset + proposal.baseSnapshot.length,
    proposal.baseSnapshot,
  );
  offset += proposal.baseSnapshot.length;
  output.setRange(offset, output.length, proposal.update);
  return output;
}

CollaborationProposal decodeProposalPayload({
  required String proposalId,
  required String authorId,
  required List<int> payload,
}) {
  if (payload.length < 9 || payload.length > kMaxAssembledBytes) {
    throw const FormatException('Invalid proposal payload length.');
  }
  final bytes = payload is Uint8List ? payload : Uint8List.fromList(payload);
  final data = ByteData.sublistView(bytes);
  if (data.getUint8(0) != kProposalPayloadVersion) {
    throw const FormatException('Unsupported proposal payload version.');
  }
  final metadataLength = data.getUint32(1, Endian.big);
  final metadataEnd = 5 + metadataLength;
  if (metadataLength > kMaxCrdtMetadataBytes ||
      metadataEnd + 4 > bytes.length) {
    throw const FormatException('Invalid proposal metadata length.');
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes.sublist(5, metadataEnd)));
  } on Object {
    throw const FormatException('Invalid proposal metadata.');
  }
  if (decoded is! Map ||
      decoded['fileId'] is! String ||
      decoded['createdAt'] is! String) {
    throw const FormatException('Proposal metadata is incomplete.');
  }
  final baseLength = data.getUint32(metadataEnd, Endian.big);
  final baseStart = metadataEnd + 4;
  final baseEnd = baseStart + baseLength;
  if (baseEnd > bytes.length) {
    throw const FormatException('Invalid proposal base snapshot length.');
  }
  final createdAt = DateTime.tryParse(decoded['createdAt']! as String);
  if (createdAt == null) {
    throw const FormatException('Invalid proposal creation time.');
  }
  return CollaborationProposal(
    proposalId: proposalId,
    fileId: decoded['fileId']! as String,
    authorId: authorId,
    baseSnapshot: Uint8List.sublistView(bytes, baseStart, baseEnd),
    update: Uint8List.sublistView(bytes, baseEnd),
    createdAt: createdAt.toUtc(),
  );
}

CollaborationProposal _proposalFromRow(Row row) => CollaborationProposal(
  proposalId: row['proposal_id']! as String,
  fileId: row['file_id']! as String,
  authorId: row['author_id']! as String,
  baseSnapshot: Uint8List.fromList(row['base_snapshot']! as List<int>),
  update: Uint8List.fromList(row['proposal_update']! as List<int>),
  createdAt: DateTime.fromMillisecondsSinceEpoch(
    row['created_at_ms']! as int,
    isUtc: true,
  ),
  status: CollaborationProposalStatus.fromWire(row['status']! as String),
  reviewNote: row['review_note'] as String?,
  resolvedBy: row['resolved_by'] as String?,
  resolvedAt: row['resolved_at_ms'] == null
      ? null
      : DateTime.fromMillisecondsSinceEpoch(
          row['resolved_at_ms']! as int,
          isUtc: true,
        ),
);

CollaborationResolution _resolutionFromRow(Row row) => CollaborationResolution(
  proposalId: row['proposal_id']! as String,
  status: CollaborationResolutionStatus.fromWire(row['status']! as String),
  resolvedBy: row['resolved_by']! as String,
  note: row['note'] as String?,
  resolvedAt: DateTime.fromMillisecondsSinceEpoch(
    row['resolved_at_ms']! as int,
    isUtc: true,
  ),
);

CollaborationOutboxEntry _outboxFromRow(Row row) {
  final decoded = jsonDecode(row['metadata_json']! as String);
  if (decoded is! Map) throw const FormatException('Invalid outbox metadata.');
  return CollaborationOutboxEntry(
    id: row['id']! as int,
    opcode:
        CrdtOpcode.fromWire(row['opcode']! as int) ??
        (throw const FormatException('Invalid outbox opcode.')),
    metadata: Map<String, Object?>.from(decoded),
    body: Uint8List.fromList(row['body']! as List<int>),
    createdAt: DateTime.fromMillisecondsSinceEpoch(
      row['created_at_ms']! as int,
      isUtc: true,
    ),
    attemptCount: row['attempt_count']! as int,
    messageId: row['message_id'] as String?,
  );
}
