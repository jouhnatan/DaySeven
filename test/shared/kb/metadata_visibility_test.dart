/// Whether `metadata/` is shown, and — more importantly — what showing it must
/// not change.
///
/// `metadata/` holds `workspace.bin` and the signed policy. Revealing it is a
/// view setting for somebody debugging sync. It must not turn those files into
/// documents that can be opened, published, or deleted.
library;

import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;
  late KnowledgeBase kb;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('ds-metadata');
    kb = await KnowledgeBase.create(folder: dir.path, name: 'Awayside');
    await kb.createDocument(title: 'Aldric');
    final yjs = Directory(
      p.join(kb.rootPath, kMetadataDirName, 'yjs'),
    )..createSync(recursive: true);
    File(p.join(yjs.path, 'workspace.bin')).writeAsBytesSync([0, 1, 2]);
    File(p.join(yjs.path, 'policy.json')).writeAsStringSync('{}');
  });

  tearDown(() => dir.deleteSync(recursive: true));

  Set<String> namesIn(List<KbNode> tree) =>
      walkKbTree(tree).map((n) => n.relativePath).toSet();

  test('metadata/ is absent from the tree by default', () async {
    final tree = await kb.readTree();
    expect(
      namesIn(tree).where((path) => path.startsWith(kMetadataDirName)),
      isEmpty,
    );
  });

  test('the developer setting reveals it', () async {
    final tree = await kb.readTree(includeMetadata: true);
    expect(
      namesIn(tree).any((path) => path.startsWith(kMetadataDirName)),
      isTrue,
    );
  });

  test('revealing it does not make it deletable', () async {
    // The guard that matters. Seeing workspace.bin in a tree must not become a
    // way to delete the workspace.
    await expectLater(
      kb.deleteNode('$kMetadataDirName/yjs/workspace.bin'),
      throwsA(isA<KbException>()),
    );
    await expectLater(
      kb.deleteNode(kMetadataDirName),
      throwsA(isA<KbException>()),
    );
  });

  test('workspace.bin is never a document, shown or not', () async {
    for (final visible in [false, true]) {
      final tree = await kb.readTree(includeMetadata: visible);
      final documents = documentPathsIn(tree);
      expect(
        documents.any((path) => path.endsWith('workspace.bin')),
        isFalse,
        reason: 'includeMetadata: $visible',
      );
      expect(
        documents.any((path) => path.endsWith('policy.json')),
        isFalse,
        reason: 'includeMetadata: $visible',
      );
    }
  });

  test('the flag defaults to off and survives a malformed settings file',
      () async {
    final file = File(p.join(dir.path, 'settings.json'));
    final store = AppStore(file);
    expect(await store.developerFlag(AppStore.showWorkspaceMetadata), isFalse);

    await store.setDeveloperFlag(AppStore.showWorkspaceMetadata, true);
    expect(await store.developerFlag(AppStore.showWorkspaceMetadata), isTrue);

    file.writeAsStringSync('{ not json');
    expect(await store.developerFlag(AppStore.showWorkspaceMetadata), isFalse);
  });

  test('packaging keeps the complete metadata directory', () async {
    // Backup, export and synchronisation must include metadata/ even though
    // the tree hides it: a workspace copied without workspace.bin has lost its
    // CRDT history and every collaborator's position in it.
    final everything = <String>[];
    await for (final entity in Directory(
      kb.rootPath,
    ).list(recursive: true, followLinks: false)) {
      if (entity is File) {
        everything.add(p.relative(entity.path, from: kb.rootPath));
      }
    }
    expect(
      everything.any((path) => path.contains('workspace.bin')),
      isTrue,
      reason: 'a recursive copy of the bundle must carry metadata/',
    );
  });
}
