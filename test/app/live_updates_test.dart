import 'dart:io';

import 'package:dayseven/app/state.dart';
import 'package:dayseven/domain/blocks.dart';
import 'package:dayseven/kb/bundle.dart';
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
          .writeAsString(
            '{"schemaVersion":1,"id":"d1","title":"Aldric",'
            '"blocks":[{"id":"b1","type":"paragraph","spans":'
            '[{"text":"He keeps the causeway."}]}]}',
          );

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
