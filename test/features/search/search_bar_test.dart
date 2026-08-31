import 'dart:io';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/shell/shell.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/search/ui/search_bar.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;
  late ProviderContainer container;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_search_bar_test');
    support = await Directory.systemTemp.createTemp(
      'dayseven_search_bar_support',
    );

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : null,
        );

    final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
    final path = await kb.createDocument(title: 'Aldric');
    final document = await kb.readDocument(path);
    await kb.writeDocument(
      path,
      document.copyWith(
        title: 'An Outdated Embedded Title',
        blocks: const [
          ParagraphBlock(
            id: 'p1',
            spans: [TextSpanNode(text: 'He keeps the causeway.')],
          ),
        ],
      ),
    );

    container = ProviderContainer();
    await container.read(kbControllerProvider.notifier).openFolder(temp.path);
  });

  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await support.exists()) await support.delete(recursive: true);
  });

  testWidgets('searches and displays the Markdown file name', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const DsShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.descendant(
      of: find.byType(DsSearchBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'Aldric');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(
      find.text('Aldric'),
      findsNWidgets(3),
      reason: 'the query, tree row and search result all use the file name',
    );
    expect(find.text('An Outdated Embedded Title'), findsNothing);
    expect(
      find.textContaining('He keeps the causeway.', findRichText: true),
      findsOneWidget,
    );
    expect(
      tester
          .getRect(
            find.textContaining('He keeps the causeway.', findRichText: true),
          )
          .top,
      greaterThan(tester.getRect(searchField).bottom),
      reason: 'top-bar Search hangs its results down over the workspace',
    );
  });

  testWidgets('opens a document when its search result is clicked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const DsShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final searchField = find.descendant(
      of: find.byType(DsSearchBar),
      matching: find.byType(TextField),
    );
    await tester.enterText(searchField, 'causeway');
    await tester.pumpAndSettle();

    final result = find.textContaining(
      'He keeps the causeway.',
      findRichText: true,
    );
    expect(result, findsOneWidget);

    // A real mouse click has time between down and up. The field must keep the
    // overlay alive throughout that interval so the row can receive onTap.
    final gesture = await tester.startGesture(
      tester.getCenter(result),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump();

    // Opening reads the document and recent-file store from real disk, so the
    // gesture that starts those futures must finish outside the fake clock.
    await tester.runAsync(() async {
      await gesture.up();
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (container.read(documentControllerProvider)?.relativePath !=
              'Aldric.md' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    expect(
      tester.widget<TextField>(searchField).controller?.text,
      isEmpty,
      reason: 'the result row received the completed click',
    );
    expect(container.read(viewProvider), DsView.editor);
    expect(
      container.read(documentControllerProvider)?.relativePath,
      'Aldric.md',
    );
  });
}
