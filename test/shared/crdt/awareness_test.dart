/// Collaborators' carets, resolved against a real yrs document.
///
/// The interesting cases are all the ones where an absolute offset would have
/// been wrong: the peer's copy has moved on, or the text their caret sat in is
/// gone.
library;

import 'dart:io';

import 'package:dayseven/shared/crdt/awareness.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/presence/peer_presence.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _file = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1';

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

PeerPresence peer({
  String? cursor,
  String? selectionAnchor,
  String documentId = _file,
}) => PeerPresence(
  userId: 'peer-1',
  username: 'haoyu',
  displayName: 'Haoyu',
  documentId: documentId,
  relativePath: 'Aldric.md',
  cursor: cursor,
  selectionAnchor: selectionAnchor,
  updatedAt: DateTime.utc(2026, 8, 26),
);

void main() {
  final path = _libraryPath();

  group('awareness', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    late Directory dir;
    late WorkspaceStore store;
    late AwarenessResolver resolver;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('ds-awareness');
      store = await WorkspaceStore.open(rootPath: dir.path, workspaceId: _kb);
      await store.upsertFile(
        fileId: _file,
        path: 'Aldric.md',
        protected: false,
        owners: const [],
      );
      await store.setFileText(fileId: _file, next: 'The moor is wide.');
      resolver = AwarenessResolver(store);
    });

    tearDown(() async {
      await store.close();
      dir.deleteSync(recursive: true);
    });

    test('a caret round-trips to the same offset', () async {
      final encoded = await resolver.encodeCaret(fileId: _file, offset: 4);
      final caret = await resolver.resolve(peer(cursor: encoded), fileId: _file);
      expect(caret!.offset, 4);
      expect(caret.hasSelection, isFalse);
    });

    test('a caret follows text inserted before it', () async {
      // This is the whole reason positions are relative. An index of 4 sent
      // before the insert would point at the wrong word after it.
      final encoded = await resolver.encodeCaret(fileId: _file, offset: 4);
      await store.setFileText(
        fileId: _file,
        next: 'Beyond, the moor is wide.',
      );
      final caret = await resolver.resolve(peer(cursor: encoded), fileId: _file);
      expect(caret!.offset, 12);
    });

    test('a caret in deleted text is clamped into the surviving document',
        () async {
      final encoded = await resolver.encodeCaret(fileId: _file, offset: 12);
      await store.setFileText(fileId: _file, next: 'Gone.');
      final caret = await resolver.resolve(peer(cursor: encoded), fileId: _file);
      final length = (await store.getFileText(_file)).length;
      expect(caret, isNotNull);
      expect(caret!.offset, lessThanOrEqualTo(length));
    });

    test('a selection resolves both ends and orders them', () async {
      final head = await resolver.encodeCaret(fileId: _file, offset: 12);
      final anchor = await resolver.encodeCaret(fileId: _file, offset: 4);
      final caret = await resolver.resolve(
        peer(cursor: head, selectionAnchor: anchor),
        fileId: _file,
      );
      expect(caret!.hasSelection, isTrue);
      expect(caret.start, 4);
      expect(caret.end, 12);
    });

    test('a selection collapsed onto the caret is a caret', () async {
      final same = await resolver.encodeCaret(fileId: _file, offset: 4);
      final caret = await resolver.resolve(
        peer(cursor: same, selectionAnchor: same),
        fileId: _file,
      );
      expect(caret!.hasSelection, isFalse);
    });

    group('what is not drawn', () {
      test('a peer in a different document', () async {
        final encoded = await resolver.encodeCaret(fileId: _file, offset: 4);
        final caret = await resolver.resolve(
          peer(cursor: encoded, documentId: 'another-file'),
          fileId: _file,
        );
        expect(caret, isNull);
      });

      test('a peer who sent no cursor at all', () async {
        // An older build. It still appears in the tree via blockId; it simply
        // has no caret to draw.
        expect(await resolver.resolve(peer(), fileId: _file), isNull);
      });

      test('a cursor that is not base64', () async {
        final caret = await resolver.resolve(
          peer(cursor: 'not base64 !!!'),
          fileId: _file,
        );
        expect(caret, isNull);
      });

      test('a cursor that is base64 but not a position', () async {
        final caret = await resolver.resolve(
          peer(cursor: 'CQkJCQkJCQk='),
          fileId: _file,
        );
        expect(caret, isNull);
      });

      test('a file this workspace does not have', () async {
        expect(
          await resolver.encodeCaret(fileId: 'no-such-file', offset: 0),
          isNull,
        );
      });

      test('a negative offset', () async {
        expect(await resolver.encodeCaret(fileId: _file, offset: -1), isNull);
      });
    });

    test('resolveAll keeps only the peers it can place', () async {
      final encoded = await resolver.encodeCaret(fileId: _file, offset: 4);
      final carets = await resolver.resolveAll([
        peer(cursor: encoded),
        peer(cursor: null),
        peer(cursor: encoded, documentId: 'elsewhere'),
      ], fileId: _file);
      expect(carets, hasLength(1));
      expect(carets.single.offset, 4);
    });

    test('presence never carries document text, only anchors', () async {
      final encoded = await resolver.encodeCaret(fileId: _file, offset: 4);
      final json = peer(cursor: encoded).toJson().toString();
      expect(json, isNot(contains('The moor')));
      expect(json, isNot(contains('wide')));
    });
  });
}
