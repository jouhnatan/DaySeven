/// Two real yrs peers converging through a stand-in for Supabase.
///
/// The relay here behaves like the real one in the ways that can break sync:
/// updates are ordered by an ever-increasing cursor, a peer catches up from a
/// cursor rather than from the beginning, and compaction folds the log into a
/// snapshot that a later peer must be able to start from. What it does not do
/// is deliver anything — that is the point. Every peer's document state comes
/// from applying bytes that actually crossed the boundary.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/generated/api/workspace.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';

const _fileId = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1';

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

/// Mirrors `public.yjs_updates` and `public.yjs_snapshots`, including the
/// cursor arithmetic in `private.yjs_pull`.
class FakeRelay {
  final List<({int id, Uint8List bytes})> _log = [];
  Uint8List? _snapshot;
  int _snapshotThrough = 0;
  int _next = 0;

  int get logLength => _log.length;
  int get snapshotThrough => _snapshotThrough;

  int push(Uint8List update) {
    _log.add((id: ++_next, bytes: update));
    return _next;
  }

  ({Uint8List? snapshot, List<Uint8List> updates, int cursor}) pull(int? since) {
    final sendSnapshot =
        _snapshot != null && (since == null || since < _snapshotThrough);
    final from = sendSnapshot ? _snapshotThrough : (since ?? 0);
    final updates = [
      for (final entry in _log)
        if (entry.id > from) entry.bytes,
    ];
    final maxId = _log.isEmpty ? 0 : _log.last.id;
    return (
      snapshot: sendSnapshot ? _snapshot : null,
      updates: updates,
      cursor: [
        maxId,
        if (sendSnapshot) _snapshotThrough else (since ?? 0),
      ].reduce((a, b) => a > b ? a : b),
    );
  }

  int compact(Uint8List snapshot, int through) {
    final before = _log.length;
    _snapshot = snapshot;
    _snapshotThrough = through;
    _log.removeWhere((entry) => entry.id <= through);
    return before - _log.length;
  }
}

/// One collaborator: a real yrs document plus the cursor it has consumed to.
class Peer {
  Peer(this.handle, this.relay);

  final BigInt handle;
  final FakeRelay relay;
  int cursor = 0;
  Uint8List? _lastSent;

  static Future<Peer> fresh(FakeRelay relay, {String id = 'awayside'}) async {
    return Peer(await workspaceCreate(workspaceId: id), relay);
  }

  /// Sends what the log is missing, exactly as CrdtSession does.
  ///
  /// The first send is the whole document. Diffing against this peer's own
  /// initial state vector instead would omit its own first operations, and
  /// every later update would then dangle causally and never integrate
  /// anywhere — silently, since Yjs buffers rather than errors.
  Future<int?> push() async {
    final since = _lastSent;
    final payload = since == null
        ? await workspaceEncode(handle: handle)
        : await workspaceDiff(handle: handle, sinceStateVector: since);
    if (isEmptyYjsUpdate(payload)) return null;
    final id = relay.push(payload);
    _lastSent = await workspaceStateVector(handle: handle);
    return id;
  }

  Future<List<String>> catchUp() async {
    final result = relay.pull(cursor == 0 ? null : cursor);
    final changed = <String>{};
    if (result.snapshot != null) {
      changed.addAll(await workspaceApply(handle: handle, update: result.snapshot!));
    }
    for (final update in result.updates) {
      changed.addAll(await workspaceApply(handle: handle, update: update));
    }
    cursor = result.cursor;
    return changed.toList();
  }

  Future<String> text([String fileId = _fileId]) =>
      fileText(handle: handle, fileId: fileId);

  Future<void> write(String text, {String fileId = _fileId}) =>
      fileSetText(handle: handle, fileId: fileId, next: text);

  Future<void> close() => workspaceClose(handle: handle);
}

void main() {
  final path = _libraryPath();

  group('CRDT relay round trip', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    late FakeRelay relay;
    setUp(() => relay = FakeRelay());

    Future<Peer> author() async {
      final peer = await Peer.fresh(relay);
      await fileUpsert(
        handle: peer.handle,
        fileId: _fileId,
        path: 'Characters/Aldric.md',
        protected: false,
        owners: const ['haoyu'],
      );
      return peer;
    }

    test('a second peer catches up to a document it never saw', () async {
      final alice = await author();
      addTearDown(alice.close);
      await alice.write('The moor is wide.');
      await alice.push();

      final bob = await Peer.fresh(relay);
      addTearDown(bob.close);
      expect(await bob.catchUp(), contains(_fileId));
      expect(await bob.text(), 'The moor is wide.');
      expect(bob.cursor, 1);
    });

    test('concurrent edits converge through the log, losing neither', () async {
      final alice = await author();
      final bob = await Peer.fresh(relay);
      addTearDown(alice.close);
      addTearDown(bob.close);
      await alice.write('The moor is wide.');
      await alice.push();
      await bob.catchUp();

      // Neither peer sees the other before writing.
      await alice.write('The moor is wide and cold.');
      await bob.write('The northern moor is wide.');
      await alice.push();
      await bob.push();

      await alice.catchUp();
      await bob.catchUp();

      final settled = await alice.text();
      expect(settled, await bob.text());
      expect(settled, contains('northern'));
      expect(settled, contains('cold'));
    });

    test('a non-ASCII filename survives the round trip', () async {
      // The real Knowledge Base contains `Oetes [Ωετες].md`. UTF-16 offsets are
      // the reason OffsetKind::Utf16 is mandatory in the Rust core; a peer
      // catching up is where a mismatch would first show as corruption.
      const otherId = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e2';
      final alice = await author();
      addTearDown(alice.close);
      await fileUpsert(
        handle: alice.handle,
        fileId: otherId,
        path: 'Places/Oetes [Ωετες].md',
        protected: false,
        owners: const ['haoyu'],
      );
      await alice.write('Ωετες lies east of the moor.', fileId: otherId);
      await alice.push();

      final bob = await Peer.fresh(relay);
      addTearDown(bob.close);
      await bob.catchUp();
      expect(await bob.text(otherId), 'Ωετες lies east of the moor.');
      expect(
        (await fileMeta(handle: bob.handle, fileId: otherId)).path,
        'Places/Oetes [Ωετες].md',
      );
    });

    test('an empty pull leaves the cursor where it was', () async {
      final alice = await author();
      addTearDown(alice.close);
      await alice.write('The moor is wide.');
      await alice.push();
      final bob = await Peer.fresh(relay);
      addTearDown(bob.close);
      await bob.catchUp();
      final settled = bob.cursor;

      // Polling a quiet log must not rewind, or every poll replays everything.
      await bob.catchUp();
      expect(bob.cursor, settled);
      expect(await bob.text(), 'The moor is wide.');
    });

    test('pushing with nothing to send writes no row', () async {
      final alice = await author();
      addTearDown(alice.close);
      await alice.write('The moor is wide.');
      await alice.push();
      final before = relay.logLength;
      expect(await alice.push(), isNull);
      expect(relay.logLength, before);
    });

    test('a peer starting after compaction still gets the whole document',
        () async {
      final alice = await author();
      addTearDown(alice.close);
      for (final line in ['One.', 'One. Two.', 'One. Two. Three.']) {
        await alice.write(line);
        await alice.push();
      }
      expect(relay.logLength, greaterThan(1));

      // The owner folds the log down, exactly as yjs_compact does.
      final folded = await workspaceEncode(handle: alice.handle);
      final reclaimed = relay.compact(folded, relay.logLength);
      expect(reclaimed, greaterThan(0));
      expect(relay.logLength, 0);

      final late_ = await Peer.fresh(relay);
      addTearDown(late_.close);
      await late_.catchUp();
      expect(await late_.text(), 'One. Two. Three.');
      expect(late_.cursor, relay.snapshotThrough);
    });

    test('edits made after compaction reach a peer that has the snapshot',
        () async {
      final alice = await author();
      addTearDown(alice.close);
      await alice.write('One.');
      await alice.push();
      relay.compact(await workspaceEncode(handle: alice.handle), relay.logLength);

      final bob = await Peer.fresh(relay);
      addTearDown(bob.close);
      await bob.catchUp();

      await alice.write('One. Two.');
      await alice.push();
      await bob.catchUp();
      expect(await bob.text(), 'One. Two.');
    });

    test('applying the same update twice changes nothing', () async {
      // Broadcast and the durable log deliver the same bytes by design. That
      // is only safe because applying an update twice is a no-op.
      final alice = await author();
      final bob = await Peer.fresh(relay);
      addTearDown(alice.close);
      addTearDown(bob.close);
      await alice.write('The moor is wide.');
      final id = await alice.push();
      expect(id, isNotNull);

      final broadcast = relay.pull(null).updates.single;
      await workspaceApply(handle: bob.handle, update: broadcast);
      final once = await bob.text();
      await workspaceApply(handle: bob.handle, update: broadcast);
      expect(await bob.text(), once);
    });
  });
}
