/// The session, driven through a fake relay and a fake channel.
///
/// Real yrs documents on both ends; only Supabase is stubbed. What is being
/// tested is the loop — catch up, judge, apply, debounce, send — and
/// particularly the parts that only misbehave under load or under attack.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:dayseven/shared/crdt/crdt_session.dart';
import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/generated/api/workspace.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/security/security_log.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _owner = 'user-owner';
const _editor = 'user-editor';

/// A second editor, so a test can send *from* an editor without it being this
/// session's own id — which the session correctly ignores.
const _otherEditor = 'user-editor-2';
const _protectedFile = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1';
const _openFile = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e2';

String? _libraryPath() {
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

final _policy = WorkspacePolicy(
  kbId: _kb,
  ownerId: _owner,
  issuedAt: DateTime.utc(2026, 8, 26),
  members: const {
    _owner: PolicyRole.owner,
    _editor: PolicyRole.editor,
    _otherEditor: PolicyRole.editor,
  },
  protectedFiles: const {
    _protectedFile: ProtectedFile(
      fileId: _protectedFile,
      minimumPublishRole: PolicyRole.owner,
    ),
  },
);

/// Stands in for Postgres. Records what was asked of it.
class FakeRepository implements CrdtSyncRepository {
  FakeRepository();

  final List<Uint8List> pushed = [];
  final List<({String fileId, Uint8List update})> proposals = [];
  final List<Uint8List> log = [];
  Object? pushError;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} not used in this test');

  @override
  Future<int> push({required String kbId, required List<int> update}) async {
    if (pushError != null) throw pushError!;
    pushed.add(Uint8List.fromList(update));
    log.add(Uint8List.fromList(update));
    return log.length;
  }

  @override
  Future<CrdtCatchUp> pull({required String kbId, int? since}) async {
    final from = since ?? 0;
    return CrdtCatchUp(
      snapshot: null,
      snapshotThrough: null,
      updates: [
        for (var i = from; i < log.length; i++)
          CrdtUpdate(id: i + 1, authorId: 'someone', bytes: log[i]),
      ],
      cursor: log.length,
    );
  }

  @override
  Future<String> submitProposal({
    required String kbId,
    required String fileId,
    required List<int> update,
  }) async {
    proposals.add((fileId: fileId, update: Uint8List.fromList(update)));
    return 'proposal-${proposals.length}';
  }
}

class MemorySink implements SecuritySink {
  final List<String> lines = [];
  @override
  void write(String line) => lines.add(line);
}

void main() {
  final path = _libraryPath();

  group('CrdtSession', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    late Directory dir;
    late WorkspaceStore store;
    late FakeRepository repository;
    late MemorySink sink;
    late SecurityLog log;
    late CrdtSession session;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ds-session');
      store = await WorkspaceStore.open(rootPath: dir.path, workspaceId: _kb);
      for (final id in [_protectedFile, _openFile]) {
        await store.upsertFile(
          fileId: id,
          path: id == _protectedFile ? 'Protected.md' : 'Open.md',
          protected: id == _protectedFile,
          owners: const [_owner],
        );
      }
      repository = FakeRepository();
      sink = MemorySink();
      log = SecurityLog(sink: sink);
      session = CrdtSession(
        kbId: _kb,
        store: store,
        repository: repository,
        authorId: _editor,
        gate: CrdtAuthorizationGate(store: store, policy: _policy),
        securityLog: log,
        // No live channel: the outbound half is exercised through push and
        // the inbound half by handing frames straight in, so a fake Realtime
        // channel would only test the fake.
        channelFactory: (_) => null,
      );
    });

    tearDown(() async {
      await store.close();
      dir.deleteSync(recursive: true);
    });

    /// A frame as a peer would send it.
    List<Map<String, dynamic>> framesFrom({
      required String senderId,
      required List<int> update,
      CrdtMessageType type = CrdtMessageType.crdtUpdate,
      String? messageId,
    }) => [
      for (final frame in encodeMessage(
        type: type,
        messageId: messageId ?? 'm-${DateTime.now().microsecondsSinceEpoch}',
        senderId: senderId,
        payload: update,
      ))
        Map<String, dynamic>.from(frame.payload),
    ];

    /// An update from a peer editing [fileId].
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

    /// Lets the session's queue drain.
    Future<void> settle() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    group('inbound', () {
      test('an allowed update from a peer is applied', () async {
        for (final frame in framesFrom(
          senderId: _owner,
          update: await peerEdit(_openFile, 'The moor is wide.'),
        )) {
          session.receiveForTest(frame);
        }
        await settle();
        expect(await store.getFileText(_openFile), 'The moor is wide.');
      });

      test('a protected edit from an editor is refused and logged', () async {
        final refusals = <CrdtDecision>[];
        session.refusals.listen(refusals.add);
        for (final frame in framesFrom(
          senderId: _otherEditor,
          update: await peerEdit(_protectedFile, 'Not reviewed.'),
        )) {
          session.receiveForTest(frame);
        }
        await settle();

        expect(await store.getFileText(_protectedFile), isEmpty);
        expect(refusals.single.verdict, CrdtVerdict.refusedProtected);
        log.flush();
        expect(sink.lines.join(), contains('authz.failed'));
      });

      test('our own broadcast is ignored rather than reapplied', () async {
        for (final frame in framesFrom(
          senderId: _editor,
          update: await peerEdit(_openFile, 'Echo.'),
        )) {
          session.receiveForTest(frame);
        }
        await settle();
        expect(await store.getFileText(_openFile), isEmpty);
      });

      test('a frame outside the protocol is logged, not applied', () async {
        session.receiveForTest({'t': 'eval', 'mid': 'x', 'sender': _owner});
        await settle();
        log.flush();
        expect(sink.lines.join(), contains('protocol.error'));
      });

      test('a replayed message is refused the second time', () async {
        final update = await peerEdit(_openFile, 'Once.');
        for (var round = 0; round < 2; round++) {
          for (final frame in framesFrom(
            senderId: _owner,
            update: update,
            messageId: 'm-fixed',
          )) {
            session.receiveForTest(frame);
          }
        }
        await settle();
        log.flush();
        expect(sink.lines.join(), contains('replay'));
      });

      test('a burst is bounded, and the excess is logged not queued', () async {
        final small = CrdtSession(
          kbId: _kb,
          store: store,
          repository: repository,
          authorId: _editor,
          gate: CrdtAuthorizationGate(store: store, policy: _policy),
          securityLog: log,
          maxInboundQueue: 4,
          channelFactory: (_) => null,
        );
        final update = await peerEdit(_openFile, 'Flood.');
        for (var i = 0; i < 200; i++) {
          for (final frame in framesFrom(
            senderId: _owner,
            update: update,
            messageId: 'm-$i',
          )) {
            small.receiveForTest(frame);
          }
        }
        expect(small.state.queuedInbound, lessThanOrEqualTo(4));
        await settle();
        log.flush();
        expect(sink.lines.join(), contains('inbound_queue'));
        await small.dispose();
      });
    });

    group('outbound', () {
      test('the first push carries the whole document', () async {
        await session.start();
        session.noteLocalChange();
        await session.flush();
        expect(repository.pushed, hasLength(1));

        // A fresh peer can reach our state from that one update alone.
        final fresh = await workspaceCreate(workspaceId: _kb);
        await workspaceApply(handle: fresh, update: repository.pushed.single);
        expect(await fileIds(handle: fresh), contains(_openFile));
        await workspaceClose(handle: fresh);
      });

      test('a push with nothing to say writes nothing', () async {
        await session.start();
        session.noteLocalChange();
        await session.flush();
        final after = repository.pushed.length;
        session.noteLocalChange();
        await session.flush();
        expect(repository.pushed, hasLength(after));
      });

      test('a failed push keeps the change pending instead of losing it',
          () async {
        await session.start();
        repository.pushError = StateError('offline');
        session.noteLocalChange();
        await session.flush();
        expect(repository.pushed, isEmpty);
        expect(session.state.pendingLocalPush, isTrue);

        // The backoff is doing its job: an immediate retry is refused. The
        // change is still pending, and goes out once the wait has elapsed.
        repository.pushError = null;
        session.noteLocalChange();
        await session.flush();
        expect(repository.pushed, isEmpty, reason: 'still backing off');

        await Future<void>.delayed(const Duration(milliseconds: 700));
        session.noteLocalChange();
        await session.flush();
        expect(repository.pushed, hasLength(1));
        expect(session.state.pendingLocalPush, isFalse);
      });

      test('a repeatedly failing push stops resending', () async {
        await session.start();
        repository.pushError = StateError('always');
        for (var i = 0; i < 50; i++) {
          session.noteLocalChange();
          await session.flush();
        }
        // The budget gives up well short of fifty attempts.
        expect(session.state.health, CrdtLinkHealth.degraded);
      });
    });

    group('proposals', () {
      test('a protected edit becomes a proposal, not a push', () async {
        await session.start();
        final id = await session.proposeChange(
          fileId: _protectedFile,
          text: 'Suggested wording.',
        );
        expect(id, 'proposal-1');
        expect(repository.proposals.single.fileId, _protectedFile);
      });

      test('proposing does not change canonical state', () async {
        // The author's own document must not contain the change, or it would
        // be pushed to the log and reach every peer as a fact.
        await session.start();
        await session.proposeChange(
          fileId: _protectedFile,
          text: 'Suggested wording.',
        );
        expect(await store.getFileText(_protectedFile), isEmpty);
      });

      test('the proposal carries the change and nothing else', () async {
        await session.start();
        await session.proposeChange(
          fileId: _protectedFile,
          text: 'Suggested wording.',
        );
        // Applying it to a copy of canonical produces exactly the edit.
        final peer = await workspaceLoad(bytes: await store.encode());
        await workspaceApply(
          handle: peer,
          update: repository.proposals.single.update,
        );
        expect(
          await fileText(handle: peer, fileId: _protectedFile),
          'Suggested wording.',
        );
        expect(await fileText(handle: peer, fileId: _openFile), isEmpty);
        await workspaceClose(handle: peer);
      });

      test('proposing nothing is refused', () async {
        await session.start();
        await expectLater(
          session.proposeChange(fileId: _protectedFile, text: ''),
          throwsA(isA<WorkspaceStoreException>()),
        );
      });
    });

    test('the security log never contains document text', () async {
      await session.start();
      for (final frame in framesFrom(
        senderId: _otherEditor,
        update: await peerEdit(_protectedFile, 'A secret paragraph of prose.'),
      )) {
        session.receiveForTest(frame);
      }
      await settle();
      log.flush();
      final everything = sink.lines.join('\n');
      expect(everything, isNot(contains('secret paragraph')));
      expect(everything, contains(_protectedFile));
      // And it is still valid JSON per line.
      for (final line in sink.lines) {
        expect(() => jsonDecode(line), returnsNormally);
      }
    });
  });
}
