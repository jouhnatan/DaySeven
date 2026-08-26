/// The receive-side gate, against real yrs documents.
///
/// Every case here is a peer sending an update this device has to decide about
/// before it touches canonical state. The gate cannot read the update — it
/// applies it to a throwaway copy, asks what changed, and judges that.
library;

import 'dart:io';

import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/generated/api/workspace.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _owner = 'user-owner';
const _editor = 'user-editor';
const _reviewer = 'user-reviewer';
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
    _reviewer: PolicyRole.reviewer,
  },
  protectedFiles: const {
    _protectedFile: ProtectedFile(
      fileId: _protectedFile,
      minimumPublishRole: PolicyRole.owner,
    ),
  },
);

void main() {
  final path = _libraryPath();

  group('CRDT authorization gate', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    late Directory dir;
    late WorkspaceStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ds-authz');
      store = await WorkspaceStore.open(rootPath: dir.path, workspaceId: _kb);
      for (final id in [_protectedFile, _openFile]) {
        await store.upsertFile(
          fileId: id,
          path: id == _protectedFile ? 'Protected.md' : 'Open.md',
          protected: id == _protectedFile,
          owners: const [_owner],
        );
      }
    });

    tearDown(() async {
      await store.close();
      dir.deleteSync(recursive: true);
    });

    /// An update from a peer that edits [fileId], produced by a real second
    /// document rather than by hand.
    Future<List<int>> peerEdit(String fileId, String text) async {
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

    CrdtAuthorizationGate gate() =>
        CrdtAuthorizationGate(store: store, policy: _policy);

    /// A Knowledge Base that has never published a policy.
    CrdtAuthorizationGate gateWithoutPolicy() =>
        CrdtAuthorizationGate(store: store, policy: null);

    test('an editor editing an unprotected file is allowed', () async {
      final decision = await gate().inspect(
        senderId: _editor,
        update: await peerEdit(_openFile, 'The moor is wide.'),
      );
      expect(decision.isAllowed, isTrue);
      expect(decision.touchedFileIds, contains(_openFile));
    });

    test('an editor editing a protected file is refused', () async {
      final decision = await gate().inspect(
        senderId: _editor,
        update: await peerEdit(_protectedFile, 'Rewritten without review.'),
      );
      expect(decision.verdict, CrdtVerdict.refusedProtected);
      expect(decision.offendingFileId, _protectedFile);
      expect(decision.detail, contains('requires owner'));
    });

    test('the owner editing a protected file is allowed', () async {
      final decision = await gate().inspect(
        senderId: _owner,
        update: await peerEdit(_protectedFile, 'Revised by the owner.'),
      );
      expect(decision.isAllowed, isTrue);
    });

    test('a reviewer is refused even on an unprotected file', () async {
      final decision = await gate().inspect(
        senderId: _reviewer,
        update: await peerEdit(_openFile, 'Reviewers cannot write.'),
      );
      expect(decision.verdict, CrdtVerdict.refusedRole);
    });

    test('a stranger is refused whatever they send', () async {
      final decision = await gate().inspect(
        senderId: 'mallory',
        update: await peerEdit(_openFile, 'Hello.'),
      );
      expect(decision.verdict, CrdtVerdict.refusedRole);
      expect(decision.detail, contains('not in the policy'));
    });

    test('inspecting never changes canonical state, even when it allows',
        () async {
      // The whole gate depends on staging being a throwaway. If inspection
      // mutated, a refused update would already have been applied.
      final before = await store.getFileText(_openFile);
      await gate().inspect(
        senderId: _editor,
        update: await peerEdit(_openFile, 'Staged only.'),
      );
      expect(await store.getFileText(_openFile), before);
    });

    test('inspecting a refused update leaves nothing behind either', () async {
      final before = await store.getFileText(_protectedFile);
      await gate().inspect(
        senderId: _editor,
        update: await peerEdit(_protectedFile, 'Should not land.'),
      );
      expect(await store.getFileText(_protectedFile), before);
    });

    test('an update touching one protected file is refused entirely',
        () async {
      // A Yjs update is atomic. Smuggling a protected edit alongside a
      // legitimate one must refuse both, because applying half is not an
      // option the format offers.
      final peer = await workspaceLoad(bytes: await store.encode());
      final before = await workspaceStateVector(handle: peer);
      await fileSetText(handle: peer, fileId: _openFile, next: 'Legitimate.');
      await fileSetText(
        handle: peer,
        fileId: _protectedFile,
        next: 'Smuggled.',
      );
      final update = await workspaceDiff(
        handle: peer,
        sinceStateVector: before,
      );
      await workspaceClose(handle: peer);

      final decision = await gate().inspect(senderId: _editor, update: update);
      expect(decision.verdict, CrdtVerdict.refusedProtected);
      expect(decision.touchedFileIds, contains(_openFile));
      expect(decision.offendingFileId, _protectedFile);
    });

    test('a malformed update is refused as malformed, not as unauthorized',
        () async {
      final decision = await gate().inspect(
        senderId: _editor,
        update: const [9, 9, 9, 9, 9, 9],
      );
      expect(decision.verdict, CrdtVerdict.refusedMalformed);
    });

    test('no policy means nothing is protected, not that anything goes',
        () async {
      // Without a policy the gate defers entirely to the server, which is
      // still checking membership on every write.
      final decision = await gateWithoutPolicy().inspect(
        senderId: 'anyone',
        update: await peerEdit(_protectedFile, 'No policy here.'),
      );
      expect(decision.isAllowed, isTrue);
    });

    group('the send-side mirror', () {
      test('an editor must propose a protected file, not broadcast it', () {
        expect(
          gate().mustProposeInsteadOfBroadcast(
            userId: _editor,
            fileId: _protectedFile,
          ),
          isTrue,
        );
      });

      test('an editor broadcasts an unprotected file directly', () {
        expect(
          gate().mustProposeInsteadOfBroadcast(
            userId: _editor,
            fileId: _openFile,
          ),
          isFalse,
        );
      });

      test('the owner broadcasts everything directly', () {
        expect(
          gate().mustProposeInsteadOfBroadcast(
            userId: _owner,
            fileId: _protectedFile,
          ),
          isFalse,
        );
      });

      test('send and receive agree, so ordinary work never trips the gate', () {
        // If these ever disagree, honest clients start getting refused and the
        // proposal path stops being the normal one.
        for (final user in [_owner, _editor, _reviewer, 'stranger']) {
          for (final file in [_openFile, _protectedFile]) {
            final wouldPropose = gate().mustProposeInsteadOfBroadcast(
              userId: user,
              fileId: file,
            );
            final wouldAllow = _policy.canWriteDirectly(
              userId: user,
              fileId: file,
            );
            expect(wouldPropose, !wouldAllow, reason: '$user / $file');
          }
        }
      });
    });
  });
}
