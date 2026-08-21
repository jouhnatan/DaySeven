/// Renders the shell to an image so the layout can be inspected.
///
/// Run with `--update-goldens` to refresh the checked shell images. They lock
/// down the side-menu headers and islands, tree guides, and bottom bar.
library;

import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/editor/ui/rich_controller.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;

  setUpAll(loadTestFonts);

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_look');
    support = await Directory.systemTemp.createTemp('dayseven_look_support');
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

  Future<ProviderContainer> seededKb(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.runAsync(() async {
      await container
          .read(kbControllerProvider.notifier)
          .openFolder(temp.path, createWithName: 'MyWorld');
      final kb = container.read(kbSessionProvider)!.kb;

      await kb.createFolder('Characters');
      await kb.createFolder('Characters/Houses');
      await kb.createFolder('Places');
      await kb.createDocument(
        title: 'Aldric',
        folderRelativePath: 'Characters',
      );
      await kb.createDocument(
        title: 'House Vane',
        folderRelativePath: 'Characters/Houses',
      );
      await kb.createDocument(title: 'Aldenmoor', folderRelativePath: 'Places');
      final timeline = await kb.createDocument(title: 'Timeline');
      await kb.writeDocument(
        timeline,
        BlockDocument(
          id: 'timeline',
          title: 'Timeline',
          blocks: [
            ParagraphBlock(
              id: 'opening',
              spans: const [TextSpanNode(text: 'The first age began here.')],
            ),
          ],
        ),
      );

      await container.read(kbControllerProvider.notifier).refreshTree();
    });

    return container;
  }

  Future<ProviderContainer> renderShell(
    WidgetTester tester,
    Brightness brightness, {
    bool knowledgeBaseVisible = true,
  }) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await seededKb(tester);
    if (!knowledgeBaseVisible) {
      await tester.runAsync(() async {
        final store = await container.read(appStoreProvider.future);
        await store.setPaneVisibility('knowledgeBase', false);
        container.read(paneVisibilityProvider);
        for (var attempt = 0; attempt < 50; attempt++) {
          if (!container.read(paneVisibilityProvider).knowledgeBase) return;
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
        throw StateError('Knowledge Base visibility was not restored');
      });
    }

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dsTheme(brightness),
          home: const DsShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('home, dark', (tester) async {
    await renderShell(tester, Brightness.dark);
    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/home_dark.png'),
    );
  });

  testWidgets('home, light', (tester) async {
    await renderShell(tester, Brightness.light);
    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/home_light.png'),
    );
  });

  testWidgets('home with Knowledge Base hidden, dark', (tester) async {
    await renderShell(tester, Brightness.dark, knowledgeBaseVisible: false);
    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/home_kb_hidden_dark.png'),
    );
  });

  testWidgets('editor with the tree open, dark', (tester) async {
    await renderShell(tester, Brightness.dark);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor_dark.png'),
    );
  });

  testWidgets('active editor toolbar island, dark', (tester) async {
    final container = await renderShell(tester, Brightness.dark);
    await tester.runAsync(
      () => container
          .read(documentControllerProvider.notifier)
          .open('Timeline.md'),
    );
    container.read(viewProvider.notifier).state = DsView.editor;
    await tester.pumpAndSettle();

    final paragraph = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.controller is RichTextController,
      description: 'document paragraph TextField',
    );
    await tester.tap(paragraph.first);
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor_toolbar_dark.png'),
    );

    await tester.pump(const Duration(milliseconds: 650));
    await tester.runAsync(
      () => container.read(documentControllerProvider.notifier).flush(),
    );
  });
}
