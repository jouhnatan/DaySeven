import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/shell/pane_widths.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Waits for [check] to hold, polling, so the test does not depend on exactly
/// how quickly the filesystem delivers its events.
Future<void> until(
  bool Function() check, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (check()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  fail('condition was never met within $timeout');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_live_test');
    support = await Directory.systemTemp.createTemp('dayseven_live_support');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await support.exists()) await support.delete(recursive: true);
  });

  Future<ProviderContainer> openKb() async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container
        .read(kbControllerProvider.notifier)
        .openFolder(temp.path, createWithName: 'MyWorld');
    return container;
  }

  List<String> treeNames(ProviderContainer container) =>
      container.read(kbSessionProvider)!.tree.map((n) => n.name).toList();

  test('a folder created outside the app appears in the tree', () async {
    final container = await openKb();
    expect(treeNames(container), isEmpty);

    // As if the user made it in Finder.
    await Directory(p.join(temp.path, 'Characters')).create();

    await until(() => treeNames(container).contains('Characters'));
  });

  test(
    'a document dropped into a folder appears and becomes searchable',
    () async {
      final container = await openKb();
      final session = container.read(kbSessionProvider)!;

      await Directory(p.join(temp.path, 'Characters')).create();
      await File(p.join(temp.path, 'Characters', 'Aldric$kDocumentExtension'))
          .writeAsString('''
---
d7: 1
schema: 1
id: "d1"
title: "Aldric"
---

<!-- d7 b1 -->
He keeps the causeway.
''');

      await until(() {
        final characters = container
            .read(kbSessionProvider)!
            .tree
            .whereType<KbFolder>()
            .where((f) => f.name == 'Characters');
        return characters.isNotEmpty && characters.single.children.isNotEmpty;
      });

      // The search index is rebuilt when the set of documents changes.
      await until(() => session.index.search('causeway').isNotEmpty);
    },
  );

  test(
    'workspace creation centralizes names, indexing, and tree refresh',
    () async {
      final container = await openKb();
      final session = container.read(kbSessionProvider)!;
      await session.kb.createDocument(title: 'Untitled');

      final document = await container
          .read(kbControllerProvider.notifier)
          .createDocument();
      final folder = await container
          .read(kbControllerProvider.notifier)
          .createFolder(name: 'CON');

      expect(document, 'Untitled 2.md');
      expect(folder, '_CON');
      expect(session.index.search('Untitled 2').single.relativePath, document);
      expect(treeNames(container), ['_CON', 'Untitled 2.md', 'Untitled.md']);
    },
  );

  test('deleting a folder outside the app removes it from the tree', () async {
    final container = await openKb();

    final folder = Directory(p.join(temp.path, 'Places'));
    await folder.create();
    await until(() => treeNames(container).contains('Places'));

    await folder.delete(recursive: true);
    await until(() => !treeNames(container).contains('Places'));
  });

  group('moving items in the tree', () {
    test(
      'a moved document follows into its new folder, and search with it',
      () async {
        final container = await openKb();
        final session = container.read(kbSessionProvider)!;

        await session.kb.createFolder('Characters');
        final path = await session.kb.createDocument(title: 'Aldric');
        final doc = await session.kb.readDocument(path);
        await session.kb.writeDocument(
          path,
          doc.copyWith(
            blocks: [
              ParagraphBlock(
                id: newId(),
                spans: const [TextSpanNode(text: 'He keeps the causeway.')],
              ),
            ],
          ),
        );
        await session.index.rebuild();
        await container.read(kbControllerProvider.notifier).refreshTree();

        await container
            .read(kbControllerProvider.notifier)
            .moveNode(path, 'Characters');

        final moved = 'Characters/Aldric$kDocumentExtension';
        expect(File(session.kb.absolutePathFor(moved)).existsSync(), isTrue);

        final hits = session.index.search('causeway');
        expect(hits, hasLength(1));
        expect(
          hits.single.relativePath,
          moved,
          reason: 'search points at where the document now is',
        );
      },
    );

    test('the open document stays open when its folder moves', () async {
      final container = await openKb();
      final session = container.read(kbSessionProvider)!;

      await session.kb.createFolder('Houses');
      await session.kb.createFolder('Characters');
      final path = await session.kb.createDocument(
        title: 'Vane',
        folderRelativePath: 'Houses',
      );
      await container.read(kbControllerProvider.notifier).refreshTree();
      await container.read(documentControllerProvider.notifier).open(path);

      await container
          .read(kbControllerProvider.notifier)
          .moveNode('Houses', 'Characters');

      expect(
        container.read(documentControllerProvider)!.relativePath,
        'Characters/Houses/Vane$kDocumentExtension',
      );
    });
  });

  test(
    'deleting a folder clears its open document, search, and recent paths',
    () async {
      final container = await openKb();
      final session = container.read(kbSessionProvider)!;

      await session.kb.createFolder('Characters/Houses');
      final outside = await session.kb.createDocument(title: 'Aldenmoor');
      final nested = await session.kb.createDocument(
        title: 'Vane',
        folderRelativePath: 'Characters/Houses',
      );
      await session.index.rebuild();
      await container.read(kbControllerProvider.notifier).refreshTree();
      await container.read(documentControllerProvider.notifier).open(outside);
      await container.read(documentControllerProvider.notifier).open(nested);

      await container
          .read(kbControllerProvider.notifier)
          .deleteNode('Characters');

      expect(
        Directory(session.kb.absolutePathFor('Characters')).existsSync(),
        isFalse,
      );
      expect(container.read(documentControllerProvider), isNull);
      expect(session.index.search('Vane'), isEmpty);
      expect(session.index.search('Aldenmoor'), hasLength(1));
      expect(treeNames(container), ['Aldenmoor.md']);

      final store = await container.read(appStoreProvider.future);
      expect(await store.recentDocuments(session.kb.manifest.kbId), [outside]);
    },
  );

  test('recent edited files track saves and renames, not opens', () async {
    final container = await openKb();
    final session = container.read(kbSessionProvider)!;
    final paths = <String>[];

    for (var index = 1; index <= 6; index++) {
      paths.add(await session.kb.createDocument(title: 'File $index'));
    }
    await container.read(kbControllerProvider.notifier).refreshTree();

    for (final path in paths) {
      await container.read(documentControllerProvider.notifier).open(path);
    }

    final store = await container.read(appStoreProvider.future);
    expect(
      await store.recentEditedDocuments(session.kb.manifest.kbId),
      isEmpty,
      reason: 'opening a file does not count as editing it',
    );

    for (final path in paths) {
      final documents = container.read(documentControllerProvider.notifier);
      await documents.open(path);
      final open = container.read(documentControllerProvider)!;
      documents.edit(
        open.document.copyWith(
          blocks: [
            ParagraphBlock(
              id: newId(),
              spans: [TextSpanNode(text: 'Saved $path')],
            ),
          ],
        ),
      );
      await documents.flush();
    }

    expect(
      await store.recentEditedDocuments(session.kb.manifest.kbId),
      paths.reversed,
    );
    expect(
      await container.read(recentEditedDocumentsProvider.future),
      paths.reversed.take(5),
      reason: 'Home exposes only the five most recently edited files',
    );

    final renamed = await container
        .read(kbControllerProvider.notifier)
        .renameDocument(paths.first, 'Renamed');

    final afterRename = await store.recentEditedDocuments(
      session.kb.manifest.kbId,
    );
    expect(afterRename.first, renamed);
    expect(afterRename, isNot(contains(paths.first)));
  });

  group('pane widths', () {
    test('dragging stops before the editor is squeezed out', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panes = container.read(paneWidthsProvider.notifier);

      // A wide drag on a narrow window: the editor keeps its minimum.
      panes.dragPanel(-5000, 900);
      final widths = container.read(paneWidthsProvider);

      expect(widths.panel, lessThanOrEqualTo(900 - widths.rail - 320));
      expect(widths.panel, greaterThanOrEqualTo(PaneWidths.minPanel));
    });

    test('the rail cannot be dragged past its limits', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panes = container.read(paneWidthsProvider.notifier);

      panes.dragRail(5000, 2000);
      expect(container.read(paneWidthsProvider).rail, PaneWidths.maxRail);

      panes.dragRail(-5000, 2000);
      expect(container.read(paneWidthsProvider).rail, PaneWidths.minRail);
    });

    test('a hidden panel releases its width to the rail and editor', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final panes = container.read(paneWidthsProvider.notifier);

      panes.dragRail(5000, 740, reservedPanelWidth: 0);

      expect(container.read(paneWidthsProvider).rail, PaneWidths.maxRail);
    });
  });

  test('the app writing to .settings does not disturb the tree', () async {
    final container = await openKb();
    final session = container.read(kbSessionProvider)!;

    await Directory(p.join(temp.path, 'Characters')).create();
    await until(() => treeNames(container).contains('Characters'));

    // Bookkeeping the app does for itself.
    await File(p.join(session.kb.settingsPath, 'scratch.tmp'))
        .writeAsString('ignored');
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect(treeNames(container), ['Characters']);
  });
}
