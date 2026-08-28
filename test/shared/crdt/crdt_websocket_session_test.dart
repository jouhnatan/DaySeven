import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/collaboration_journal.dart';
import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:dayseven/shared/crdt/crdt_session.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:dayseven/shared/crdt/generated/api/workspace.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

const kbId = '01a01830-9749-7398-9626-dab25d46040e';
const owner = 'user-owner';
const editor = 'user-editor';
const otherEditor = 'user-editor-2';
const protectedFile = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1';
const openFile = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e2';

String? libraryPath() {
  final root = Directory.current.path;
  for (final candidate in [
    '$root/rust/target/release/libdayseven_crdt.dylib',
    '$root/rust/target/debug/libdayseven_crdt.dylib',
    '$root/rust/target/release/dayseven_crdt.dll',
    '$root/rust/target/release/libdayseven_crdt.so',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

class SentMessage {
  const SentMessage(this.opcode, this.metadata, this.body, this.messageId);
  final CrdtOpcode opcode;
  final Map<String, Object?> metadata;
  final Uint8List body;
  final String messageId;
}

class FakeTransport implements CrdtTransport {
  final stateController = StreamController<CrdtConnectionState>.broadcast();
  final eventController = StreamController<CrdtEnvelope>.broadcast();
  final errorController = StreamController<CrdtTransportError>.broadcast();
  final sent = <SentMessage>[];
  int counter = 0;

  @override
  String get roomId => kbId;
  @override
  Uri get connectionUri => Uri.parse('wss://relay.test/ws?room=$kbId');
  @override
  CrdtConnectionState state = CrdtConnectionState.disconnected;
  @override
  Stream<CrdtConnectionState> get states => stateController.stream;
  @override
  Stream<CrdtEnvelope> get events => eventController.stream;
  @override
  Stream<CrdtTransportError> get errors => errorController.stream;

  @override
  Future<void> connect() async {
    state = CrdtConnectionState.connected;
    stateController.add(state);
  }

  @override
  Future<void> disconnect() async {
    state = CrdtConnectionState.disconnected;
    stateController.add(state);
  }

  @override
  Future<String> reconcile(Uint8List stateVector) => send(
    opcode: CrdtOpcode.stateVectorRequest,
    body: stateVector,
  );

  @override
  Future<String> send({
    required CrdtOpcode opcode,
    Map<String, Object?> metadata = const {},
    List<int> body = const [],
    String? messageId,
  }) async {
    final id = messageId ?? 'sent-${counter++}';
    sent.add(
      SentMessage(
        opcode,
        Map<String, Object?>.from(metadata),
        Uint8List.fromList(body),
        id,
      ),
    );
    return id;
  }

  void inject({
    required CrdtOpcode opcode,
    required String senderId,
    String senderRole = 'owner',
    Map<String, Object?> metadata = const {},
    List<int> body = const [],
    String messageId = 'inbound',
  }) {
    eventController.add(
      CrdtEnvelope(
        opcode: opcode,
        metadata: {
          ...metadata,
          'messageId': messageId,
          'senderId': senderId,
          'senderRole': senderRole,
        },
        body: Uint8List.fromList(body),
      ),
    );
  }
}

final policy = WorkspacePolicy(
  kbId: kbId,
  ownerId: owner,
  issuedAt: DateTime.utc(2026, 8, 28),
  members: const {
    owner: PolicyRole.owner,
    editor: PolicyRole.editor,
    otherEditor: PolicyRole.editor,
  },
  protectedFiles: const {
    protectedFile: ProtectedFile(
      fileId: protectedFile,
      minimumPublishRole: PolicyRole.owner,
    ),
  },
);

void main() {
  final dylib = libraryPath();

  group('CrdtSession over relay transport', () {
    setUpAll(() async {
      if (dylib != null) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(dylib));
      }
    });

    late Directory root;
    late WorkspaceStore store;
    late CollaborationJournal journal;
    late FakeTransport transport;
    late CrdtSession session;

    setUp(() async {
      if (dylib == null) return;
      root = Directory.systemTemp.createTempSync('dayseven-session-');
      store = await WorkspaceStore.open(rootPath: root.path, workspaceId: kbId);
      await store.upsertFile(
        fileId: protectedFile,
        path: 'Protected.md',
        protected: true,
        owners: const [owner],
      );
      await store.upsertFile(
        fileId: openFile,
        path: 'Open.md',
        protected: false,
        owners: const [owner],
      );
      journal = await CollaborationJournal.open(rootPath: root.path);
      transport = FakeTransport();
      session = CrdtSession(
        kbId: kbId,
        store: store,
        authorId: editor,
        gate: CrdtAuthorizationGate(store: store, policy: policy),
        transport: transport,
        journal: journal,
      );
    });

    tearDown(() async {
      if (dylib == null) return;
      await session.dispose();
      await store.close();
      root.deleteSync(recursive: true);
    });

    Future<void> settle() async {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    Future<Uint8List> peerEdit(String fileId, String text) async {
      final peer = await workspaceLoad(bytes: await store.encode());
      final before = await workspaceStateVector(handle: peer);
      await fileSetText(handle: peer, fileId: fileId, next: text);
      final update = await workspaceDiff(
        handle: peer,
        sinceStateVector: before,
      );
      await workspaceClose(handle: peer);
      return update;
    }

    test('connect sends state vector and proposal inventory', () async {
      if (dylib == null) return;
      await session.connect();
      await settle();

      expect(session.state.connection, CrdtConnectionState.connected);
      expect(session.state.waitingForPeer, isTrue);
      expect(
        transport.sent.map((message) => message.opcode),
        containsAll([
          CrdtOpcode.stateVectorRequest,
          CrdtOpcode.proposalInventory,
        ]),
      );
    });

    test('applies an allowed update serially without rebroadcast', () async {
      if (dylib == null) return;
      await session.connect();
      transport.sent.clear();
      transport.inject(
        opcode: CrdtOpcode.crdtUpdate,
        senderId: owner,
        body: await peerEdit(openFile, 'The moor is wide.'),
      );
      await settle();

      expect(await store.getFileText(openFile), 'The moor is wide.');
      expect(
        transport.sent.where((message) => message.opcode == CrdtOpcode.crdtUpdate),
        isEmpty,
      );
      expect(
        transport.sent.where((message) => message.opcode == CrdtOpcode.ack),
        hasLength(1),
      );
    });

    test('refuses protected direct edits from an editor', () async {
      if (dylib == null) return;
      await session.connect();
      final refusal = session.refusals.first;
      transport.inject(
        opcode: CrdtOpcode.crdtUpdate,
        senderId: otherEditor,
        senderRole: 'editor',
        body: await peerEdit(protectedFile, 'Not reviewed.'),
      );

      expect((await refusal).verdict, CrdtVerdict.refusedProtected);
      expect(await store.getFileText(protectedFile), isEmpty);
    });

    test('local changes enter the durable outbox and clear on ack', () async {
      if (dylib == null) return;
      await session.connect();
      await settle();
      transport.sent.clear();
      await store.setFileText(fileId: openFile, next: 'Local first.');
      session.noteLocalChange();
      await session.flush();

      final outbound = transport.sent.singleWhere(
        (message) => message.opcode == CrdtOpcode.crdtUpdate,
      );
      expect(journal.pendingOutbox(), hasLength(1));
      transport.inject(
        opcode: CrdtOpcode.ack,
        senderId: owner,
        metadata: {'ackedMessageId': outbound.messageId},
      );
      await settle();
      expect(journal.pendingOutbox(), isEmpty);
    });

    test('an unacknowledged update is not resent by every later drain',
        () async {
      if (dylib == null) return;
      await session.connect();
      await settle();
      transport.sent.clear();
      await store.setFileText(fileId: openFile, next: 'Sent once.');
      session.noteLocalChange();
      await session.flush();
      // Draining again while the relay has not acked must not put a second
      // copy on the wire, nor rewrite the message id the ack will name.
      await session.flush();
      await settle();

      expect(
        transport.sent.where((m) => m.opcode == CrdtOpcode.crdtUpdate),
        hasLength(1),
      );
      final outbound = transport.sent.singleWhere(
        (message) => message.opcode == CrdtOpcode.crdtUpdate,
      );
      transport.inject(
        opcode: CrdtOpcode.ack,
        senderId: owner,
        metadata: {'ackedMessageId': outbound.messageId},
      );
      await settle();
      expect(journal.pendingOutbox(), isEmpty);
    });

    test('state vector requests receive only the missing CRDT diff', () async {
      if (dylib == null) return;
      await store.setFileText(fileId: openFile, next: 'Known locally.');
      await session.connect();
      transport.sent.clear();
      final emptyPeer = await workspaceCreate(workspaceId: kbId);
      final vector = await workspaceStateVector(handle: emptyPeer);
      await workspaceClose(handle: emptyPeer);

      transport.inject(
        opcode: CrdtOpcode.stateVectorRequest,
        senderId: owner,
        body: vector,
      );
      await settle();

      expect(
        transport.sent.where((message) => message.opcode == CrdtOpcode.crdtUpdate),
        hasLength(1),
      );
    });

    test('protected proposal is journaled without changing canonical state', () async {
      if (dylib == null) return;
      await session.connect();
      final id = await session.proposeChange(
        fileId: protectedFile,
        text: 'Suggested wording.',
      );

      expect(await store.getFileText(protectedFile), isEmpty);
      expect(journal.proposal(id)!.update, isNotEmpty);
      expect(
        transport.sent.where((message) => message.opcode == CrdtOpcode.proposalData),
        isNotEmpty,
      );
    });

    test('presence is surfaced as typed ephemeral data', () async {
      if (dylib == null) return;
      await session.connect();
      final presence = session.presenceEvents.first;
      transport.inject(
        opcode: CrdtOpcode.presence,
        senderId: owner,
        body: Uint8List.fromList('{"documentId":"$openFile"}'.codeUnits),
      );

      final event = await presence;
      expect(event.userId, owner);
      expect(event.payload['documentId'], openFile);
    });

    test('inventory requests known proposals whose resolution is missing', () async {
      if (dylib == null) return;
      final known = CollaborationProposal(
        proposalId: 'proposal-1',
        fileId: protectedFile,
        authorId: otherEditor,
        baseSnapshot: await store.encode(),
        update: await peerEdit(protectedFile, 'Suggestion.'),
        createdAt: DateTime.utc(2026, 8, 28),
      );
      journal.saveProposal(known);
      await session.connect();
      transport.sent.clear();
      transport.inject(
        opcode: CrdtOpcode.proposalInventory,
        senderId: owner,
        metadata: const {
          'proposalIds': ['proposal-1'],
          'resolvedProposalIds': ['proposal-1'],
        },
      );
      await settle();

      expect(
        transport.sent.where(
          (message) =>
              message.opcode == CrdtOpcode.proposalRequest &&
              message.metadata['proposalId'] == 'proposal-1',
        ),
        hasLength(1),
      );
    });
  });
}
