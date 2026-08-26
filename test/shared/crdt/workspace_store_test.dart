import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/kb/bundle.dart';

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

Future<void> _createAwaysideFixture(KnowledgeBase kb) async {
  final files = <String, String>{
    'Overview.md': 'The world of Awayside is vast and ancient.',
    'Rules.md': 'Magic is bounded by memory and stone.',
    'Characters/Aldric.md': 'Aldric stands upon the high moor.',
    'Characters/Brynn.md': 'Brynn watches the tree line in silence.',
    'Characters/Oetes [Ωετες].md': 'Oetes [Ωετες] holds the ancient threshold.',
    'Places/Aldenmoor.md': 'Aldenmoor is cold and shrouded in mist.',
    'Places/Deep Forest.md': 'The trees are ancient and close.',
    'Places/Nested/Shrine.md': 'A stone shrine carved into the hill.',
    'Lore/History.md': 'Long before the fen, there was the hearth.',
  };

  for (final entry in files.entries) {
    final rel = entry.key;
    final text = entry.value;
    final parent = p.posix.dirname(rel);
    if (parent != '.') {
      await kb.createFolder(parent);
    }
    final doc = BlockDocument(
      id: newId(),
      title: documentTitleFromPath(rel),
      blocks: [
        ParagraphBlock(
          id: newId(),
          spans: [TextSpanNode(text: text)],
        ),
      ],
    );
    await kb.writeDocument(rel, doc);
  }
}

void main() {
  final libPath = _libraryPath();

  group('WorkspaceStore', () {
    late Directory tempDir;
    late KnowledgeBase kb;

    setUpAll(() async {
      if (libPath != null) {
        await RustLib.init(externalLibrary: ExternalLibrary.open(libPath));
      }
    });

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('workspace_store_test_');
      kb = await KnowledgeBase.create(
        folder: tempDir.path,
        name: 'Awayside',
        kbId: 'awayside-test-kb',
      );
      await _createAwaysideFixture(kb);
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Markdown import on first open of an existing KB', () async {
      final store = await WorkspaceStore.openFor(kb);
      try {
        expect(
          await Directory(store.metadataYjsPath).exists(),
          isTrue,
          reason: 'metadata/yjs directory must be created',
        );

        final ids = await store.getFileIds();
        expect(ids.length, 9, reason: 'All 9 fixture documents must be imported');

        // Check non-ASCII filename and content
        var foundOetes = false;
        for (final id in ids) {
          final meta = await store.getFileMeta(id);
          final text = await store.getFileText(id);
          expect(text, isNotEmpty);
          if (meta.path == 'Characters/Oetes [Ωετες].md') {
            foundOetes = true;
            expect(text, contains('Oetes [Ωετες]'));
          }
        }
        expect(foundOetes, isTrue, reason: 'Oetes [Ωετες].md must be found and imported');
      } finally {
        await store.close();
      }
    });

    test('workspace.bin restoration across a close/reopen', () async {
      final store1 = await WorkspaceStore.openFor(kb);
      final ids1 = await store1.getFileIds();
      String? matchedAldricId;
      for (final id in ids1) {
        final meta = await store1.getFileMeta(id);
        if (meta.path == 'Characters/Aldric.md') {
          matchedAldricId = id;
          break;
        }
      }
      expect(matchedAldricId, isNotNull);

      await store1.setFileText(
        fileId: matchedAldricId!,
        next: 'Aldric stands upon the high moor and looks north.',
      );
      await store1.flush();
      expect(await File(store1.workspaceBinPath).exists(), isTrue);
      await store1.close();

      // Reopen
      final store2 = await WorkspaceStore.openFor(kb);
      try {
        final ids2 = await store2.getFileIds();
        expect(ids2.length, 9);
        expect(ids2, contains(matchedAldricId));

        final restoredAldric = await store2.getFileText(matchedAldricId);
        expect(restoredAldric, contains('looks north'));
      } finally {
        await store2.close();
      }
    });

    test('Atomic-write recovery: kill mid-write, previous good file survives', () async {
      final store = await WorkspaceStore.openFor(kb);
      await store.flush();

      final binFile = File(store.workspaceBinPath);
      expect(await binFile.exists(), isTrue);
      final goodBytes = await binFile.readAsBytes();
      await store.close();

      // Simulate a crash mid-write leaving a corrupted .tmp file
      final tmpFile = File(store.workspaceTmpPath);
      await tmpFile.writeAsBytes([0xde, 0xad, 0xbe, 0xef, 0x00, 0x11], flush: true);

      // Reopening should succeed using the intact workspace.bin
      final store2 = await WorkspaceStore.openFor(kb);
      try {
        final ids = await store2.getFileIds();
        expect(ids.length, 9);
        final currentBytes = await File(store2.workspaceBinPath).readAsBytes();
        expect(currentBytes, goodBytes);
      } finally {
        await store2.close();
      }
    });

    test('External file edit applied as an incremental change, not a wholesale Y.Text replacement', () async {
      final storeA = await WorkspaceStore.openFor(kb);
      await storeA.flush();

      // Clone store B from store A's bytes
      final binBytes = await storeA.encode();
      final tempDirB = await Directory.systemTemp.createTemp('workspace_store_test_b_');
      final kbB = await KnowledgeBase.create(
        folder: tempDirB.path,
        name: 'Awayside B',
        kbId: 'awayside-test-kb',
      );
      final metaDirB = Directory(p.join(tempDirB.path, kMetadataDirName, kYjsSubdirName));
      await metaDirB.create(recursive: true);
      await File(p.join(metaDirB.path, kWorkspaceBinName)).writeAsBytes(binBytes, flush: true);

      final storeB = await WorkspaceStore.openFor(kbB);
      await storeB.materializeAll();

      try {
        final ids = await storeA.getFileIds();
        String? aldricId;
        for (final id in ids) {
          final meta = await storeA.getFileMeta(id);
          if (meta.path == 'Characters/Aldric.md') {
            aldricId = id;
            break;
          }
        }
        expect(aldricId, isNotNull);

        // Store A edits end of paragraph
        await storeA.setFileText(
          fileId: aldricId!,
          next: 'Aldric stands upon the high moor. The night is cold.',
        );

        // External editor edits beginning of paragraph in B's working copy on disk
        final aldricFileB = File(p.join(tempDirB.path, 'Characters/Aldric.md'));
        await aldricFileB.writeAsString(
          'Sir Aldric stands upon the high moor.',
          flush: true,
        );
        await storeB.applyExternalEdit('Characters/Aldric.md');

        // Exchange incremental updates
        final diffAtoB = await storeA.diff(await storeB.stateVector());
        final diffBtoA = await storeB.diff(await storeA.stateVector());

        await storeB.applyUpdate(diffAtoB);
        await storeA.applyUpdate(diffBtoA);

        final textA = await storeA.getFileText(aldricId);
        final textB = await storeB.getFileText(aldricId);

        expect(textA, textB, reason: 'Both stores must converge');
        expect(textA, contains('Sir Aldric'));
        expect(textA, contains('night is cold'));
      } finally {
        await storeA.close();
        await storeB.close();
        if (await tempDirB.exists()) {
          await tempDirB.delete(recursive: true);
        }
      }
    });

    test('File rename handling', () async {
      final store = await WorkspaceStore.openFor(kb);
      try {
        final ids = await store.getFileIds();
        String? aldricId;
        for (final id in ids) {
          final meta = await store.getFileMeta(id);
          if (meta.path == 'Characters/Aldric.md') {
            aldricId = id;
            break;
          }
        }
        expect(aldricId, isNotNull);

        // Rename via KB and inform store
        final newPath = await kb.renameDocument('Characters/Aldric.md', 'Aldric The Brave');
        await store.handleFileRenamed(oldPath: 'Characters/Aldric.md', newPath: newPath);

        final meta = await store.getFileMeta(aldricId!);
        expect(meta.path, 'Characters/Aldric The Brave.md');

        final text = await store.getFileText(aldricId);
        expect(text, contains('Aldric'));
      } finally {
        await store.close();
      }
    });

    test('Path traversal and symlink-escape attempts are rejected', () async {
      final store = await WorkspaceStore.openFor(kb);
      try {
        expect(
          () => store.validateDocumentPath('../outside.md'),
          throwsA(isA<PathSecurityException>()),
        );
        expect(
          () => store.validateDocumentPath('/etc/passwd.md'),
          throwsA(isA<PathSecurityException>()),
        );
        expect(
          () => store.validateDocumentPath('Characters/../../outside.md'),
          throwsA(isA<PathSecurityException>()),
        );
        expect(
          () => store.validateDocumentPath('Characters/Aldric.txt'),
          throwsA(isA<PathSecurityException>()),
        );
        expect(
          () => store.validateDocumentPath('.settings/dayseven.kb.json'),
          throwsA(isA<PathSecurityException>()),
        );
        expect(
          () => store.validateDocumentPath('metadata/yjs/workspace.bin'),
          throwsA(isA<PathSecurityException>()),
        );

        // Test symlink escaping root
        final outsideTemp = await Directory.systemTemp.createTemp('escape_target_');
        final outsideFile = File(p.join(outsideTemp.path, 'Secret.md'));
        await outsideFile.writeAsString('Secret content');

        final linkPath = p.join(tempDir.path, 'Characters', 'LinkOutside.md');
        final link = Link(linkPath);
        await link.create(outsideFile.path);

        expect(
          () => store.validateDocumentPath('Characters/LinkOutside.md'),
          throwsA(isA<PathSecurityException>()),
        );

        if (await outsideTemp.exists()) {
          await outsideTemp.delete(recursive: true);
        }
      } finally {
        await store.close();
      }
    });

    test('metadata/ absent from the tree and from search results', () async {
      final store = await WorkspaceStore.openFor(kb);
      await store.flush();
      await store.close();

      // Read tree through KnowledgeBase
      final tree = await kb.readTree();
      final paths = documentPathsIn(tree).toList();

      for (final pth in paths) {
        expect(pth.startsWith('metadata'), isFalse);
        expect(pth.contains('workspace.bin'), isFalse);
      }
      expect(paths.length, 9);

      // Search index rebuild
      final index = await SearchIndex.openFor(kb);
      try {
        await index.rebuild();
        final results = index.search('workspace');
        expect(results, isEmpty, reason: 'metadata/ contents must not appear in search results');

        final aldricResults = index.search('Aldric');
        expect(aldricResults, isNotEmpty);
      } finally {
        index.close();
      }
    });

    test('Workspace size limit is enforced', () async {
      final store = await WorkspaceStore.open(
        rootPath: tempDir.path,
        workspaceId: 'size-test',
        maxWorkspaceBytes: 100, // Small limit
      );
      try {
        expect(
          store.flush(),
          throwsA(isA<WorkspaceSizeExceededException>()),
        );
      } finally {
        await store.close();
      }
    });

    test('Materialise writes atomically and suppresses self-generated watcher events', () async {
      final store = await WorkspaceStore.openFor(kb);
      try {
        final ids = await store.getFileIds();
        String? matchedBrynnId;
        for (final id in ids) {
          final meta = await store.getFileMeta(id);
          if (meta.path == 'Characters/Brynn.md') {
            matchedBrynnId = id;
            break;
          }
        }
        expect(matchedBrynnId, isNotNull);

        await store.setFileText(
          fileId: matchedBrynnId!,
          next: 'Brynn watches the twilight descend.',
        );
        await store.materializeFile(matchedBrynnId);

        // Target file updated
        final content = await File(p.join(tempDir.path, 'Characters/Brynn.md')).readAsString();
        expect(content, 'Brynn watches the twilight descend.');

        // Watcher suppression
        expect(store.shouldSuppressWatcher('Characters/Brynn.md'), isTrue);
        expect(store.shouldSuppressWatcher('Characters/Brynn.md'), isFalse);
      } finally {
        await store.close();
      }
    });
  }, skip: libPath == null ? 'Native library not found' : false);
}
