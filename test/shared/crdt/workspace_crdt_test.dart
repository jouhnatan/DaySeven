/// Proves the CRDT core is reachable from Dart, and behaves.
///
/// The Rust crate has its own unit tests; these exist to catch the things only
/// the boundary can break — offsets disagreeing between Dart's UTF-16 strings
/// and the document, bytes being mangled in transit, and errors surfacing as
/// exceptions rather than crashing the isolate.
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/shared/crdt/generated/api/workspace.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';

const _fileId = '0192f3aa-6a1c-7c3d-9b2e-4f0d61a2c8e1';

/// Where `cargo build` leaves the library for the host platform.
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

Future<BigInt> _workspaceWith(String text) async {
  final ws = await workspaceCreate(workspaceId: 'awayside');
  await fileUpsert(
    handle: ws,
    fileId: _fileId,
    path: 'Characters/Aldric.md',
    protected: false,
    owners: ['haoyu'],
  );
  await fileSetText(handle: ws, fileId: _fileId, next: text);
  return ws;
}

void main() {
  final path = _libraryPath();

  group('workspace CRDT over the Rust bridge', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    test('a workspace round-trips through workspace.bin bytes', () async {
      final a = await _workspaceWith('The moor is wide.');
      final bin = await workspaceEncode(handle: a);
      expect(bin, isNotEmpty);

      final b = await workspaceLoad(bytes: bin);
      expect(await workspaceId(handle: b), 'awayside');
      expect(await fileText(handle: b, fileId: _fileId), 'The moor is wide.');

      final meta = await fileMeta(handle: b, fileId: _fileId);
      expect(meta.path, 'Characters/Aldric.md');
      expect(meta.protected, isFalse);
      expect(meta.owners, ['haoyu']);
    });

    test('two peers editing at once converge, losing neither edit', () async {
      final a = await _workspaceWith('The moor is wide.');
      final b = await workspaceLoad(bytes: await workspaceEncode(handle: a));

      await fileSetText(
        handle: a,
        fileId: _fileId,
        next: 'The wide moor is wide.',
      );
      await fileSetText(
        handle: b,
        fileId: _fileId,
        next: 'The moor is wide. Aldenmoor.',
      );

      final aToB = await workspaceDiff(
        handle: a,
        sinceStateVector: await workspaceStateVector(handle: b),
      );
      final bToA = await workspaceDiff(
        handle: b,
        sinceStateVector: await workspaceStateVector(handle: a),
      );
      await workspaceApply(handle: b, update: aToB);
      await workspaceApply(handle: a, update: bToA);

      final left = await fileText(handle: a, fileId: _fileId);
      final right = await fileText(handle: b, fileId: _fileId);
      expect(left, right, reason: 'peers diverged');
      expect(left, contains('wide moor'));
      expect(left, contains('Aldenmoor'));
    });

    test('an incremental update is small enough for a broadcast payload', () async {
      final a = await _workspaceWith('The moor is wide.');
      final b = await workspaceLoad(bytes: await workspaceEncode(handle: a));

      await fileSetText(
        handle: a,
        fileId: _fileId,
        next: 'The moor is wide and cold.',
      );
      final update = await workspaceDiff(
        handle: a,
        sinceStateVector: await workspaceStateVector(handle: b),
      );

      // Supabase Realtime caps a payload at 256 KB; base64 costs ~33%.
      // A single-paragraph edit should not be remotely close to that.
      expect(update.length, lessThan(1024));
    });

    test('staging reports touched files without moving canonical state', () async {
      final a = await _workspaceWith('The moor is wide.');
      final b = await workspaceLoad(bytes: await workspaceEncode(handle: a));

      await fileSetText(
        handle: b,
        fileId: _fileId,
        next: 'The moor is wide and cold.',
      );
      final update = await workspaceDiff(
        handle: b,
        sinceStateVector: await workspaceStateVector(handle: a),
      );

      expect(await workspaceStageApply(handle: a, update: update), [_fileId]);
      expect(
        await fileText(handle: a, fileId: _fileId),
        'The moor is wide.',
        reason: 'staging must not touch canonical state',
      );

      expect(await workspaceApply(handle: a, update: update), [_fileId]);
      expect(
        await fileText(handle: a, fileId: _fileId),
        'The moor is wide and cold.',
      );
    });

    test('non-ASCII text survives the boundary intact', () async {
      // The tree already holds `Oetes [Ωετες].md`. Dart strings are UTF-16 and
      // the document is configured to match; if that ever drifts, text is
      // silently corrupted rather than throwing.
      final ws = await _workspaceWith('Oetes [Ωετες] holds');
      await fileSetText(
        handle: ws,
        fileId: _fileId,
        next: 'Oetes [Ωετες] holds fast',
      );
      expect(
        await fileText(handle: ws, fileId: _fileId),
        'Oetes [Ωετες] holds fast',
      );

      await fileSetText(handle: ws, fileId: _fileId, next: '𝔄 emoji 🜃 test');
      expect(await fileText(handle: ws, fileId: _fileId), '𝔄 emoji 🜃 test');
    });

    test('a malformed workspace is refused, not half-applied', () async {
      // Rust returns Result<_, String>, so the bridge throws the message.
      await expectLater(
        workspaceLoad(bytes: [0xde, 0xad, 0xbe, 0xef]),
        throwsA(predicate((e) => '$e'.contains('malformed'))),
      );
    });

    test('an unknown handle raises rather than crashing the isolate', () async {
      await expectLater(
        fileText(handle: BigInt.from(999999), fileId: _fileId),
        throwsA(predicate((e) => '$e'.contains('no open workspace'))),
      );
    });
  },
      skip: path == null
          ? 'native library not built — run: cargo build --release --manifest-path rust/Cargo.toml'
          : false);
}
