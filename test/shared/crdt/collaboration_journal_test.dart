import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/collaboration_journal.dart';
import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late CollaborationJournal journal;

  CollaborationProposal proposal({String id = 'proposal-1'}) =>
      CollaborationProposal(
        proposalId: id,
        fileId: 'file-1',
        authorId: 'author-1',
        baseSnapshot: Uint8List.fromList([1, 2, 3]),
        update: Uint8List.fromList([4, 5, 6]),
        createdAt: DateTime.utc(2026, 8, 28, 12),
      );

  setUp(() async {
    root = Directory.systemTemp.createTempSync('dayseven-journal-');
    journal = await CollaborationJournal.open(rootPath: root.path);
  });

  tearDown(() {
    journal.close();
    root.deleteSync(recursive: true);
  });

  test('opens at metadata/yjs/collaboration.sqlite', () {
    expect(
      journal.path,
      p.join(root.path, 'metadata', 'yjs', 'collaboration.sqlite'),
    );
    expect(File(journal.path).existsSync(), isTrue);
  });

  test('persists proposal base, delta and status across reopen', () async {
    journal.saveProposal(proposal());
    journal.close();
    journal = await CollaborationJournal.open(rootPath: root.path);

    final restored = journal.proposal('proposal-1')!;
    expect(restored.fileId, 'file-1');
    expect(restored.authorId, 'author-1');
    expect(restored.baseSnapshot, [1, 2, 3]);
    expect(restored.update, [4, 5, 6]);
    expect(restored.status, CollaborationProposalStatus.pending);
  });

  test('first proposal resolution wins', () {
    journal.saveProposal(proposal());
    final first = journal.recordResolution(
      CollaborationResolution(
        proposalId: 'proposal-1',
        status: CollaborationResolutionStatus.approved,
        resolvedBy: 'owner-1',
        resolvedAt: DateTime.utc(2026, 8, 28, 13),
      ),
    );
    final second = journal.recordResolution(
      CollaborationResolution(
        proposalId: 'proposal-1',
        status: CollaborationResolutionStatus.rejected,
        resolvedBy: 'owner-2',
        resolvedAt: DateTime.utc(2026, 8, 28, 14),
      ),
    );

    expect(first.accepted, isTrue);
    expect(second.accepted, isFalse);
    expect(second.resolution.status, CollaborationResolutionStatus.approved);
    expect(
      journal.proposal('proposal-1')!.status,
      CollaborationProposalStatus.approved,
    );
  });

  test('outbox survives restart and is removed by acknowledgement', () async {
    final id = journal.enqueue(
      opcode: CrdtOpcode.crdtUpdate,
      metadata: const {'senderId': 'must-not-persist'},
      body: const [1, 2, 3],
    );
    journal.markAttempt(id, 'network-message');
    journal.close();
    journal = await CollaborationJournal.open(rootPath: root.path);

    final restored = journal.pendingOutbox().single;
    expect(restored.messageId, 'network-message');
    expect(restored.attemptCount, 1);
    expect(restored.metadata, isEmpty);
    expect(restored.body, [1, 2, 3]);

    journal.acknowledge('network-message');
    expect(journal.pendingOutbox(), isEmpty);
  });

  test('opaque proposal payload round-trips without trusting author bytes', () {
    final original = proposal();
    final decoded = decodeProposalPayload(
      proposalId: original.proposalId,
      authorId: 'server-attributed-author',
      payload: encodeProposalPayload(original),
    );

    expect(decoded.fileId, original.fileId);
    expect(decoded.authorId, 'server-attributed-author');
    expect(decoded.baseSnapshot, original.baseSnapshot);
    expect(decoded.update, original.update);
    expect(decoded.createdAt, original.createdAt);
  });
}
