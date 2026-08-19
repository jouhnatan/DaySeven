/// Renders the shell to an image so the layout can be inspected.
///
/// Run with `--update-goldens` to refresh `goldens/shell_dark.png`; the checked
/// image is what the three islands, the tree's connector lines and the bottom
/// bar are meant to look like.
library;

import 'dart:io';

import 'package:dayseven/app/state.dart';
import 'package:dayseven/app/theme.dart';
import 'package:dayseven/ui/shell/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_fonts.dart';

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
      await kb.createDocument(title: 'Timeline');

      await container.read(kbControllerProvider.notifier).refreshTree();
    });

    return container;
  }

  Future<void> renderShell(WidgetTester tester, Brightness brightness) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final container = await seededKb(tester);

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

  testWidgets('editor with the tree open, dark', (tester) async {
    await renderShell(tester, Brightness.dark);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(DsShell),
      matchesGoldenFile('goldens/editor_dark.png'),
    );
  });
}
