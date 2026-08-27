/// Test helper for Knowledge Base setup.
///
/// De-duplicates the temp-directory + `path_provider` mock + seeded content
/// that is repeated across `test/app/workspace/` and `test/app/shell/`.
///
/// The helpers are intentionally small — they remove boilerplate but do not
/// hide business logic. Callers still own the Knowledge Base contents they
/// assert on.
///
/// Usage in a test file:
///
/// ```dart
/// late Directory temp;
/// late Directory support;
///
/// setUp(() async {
///   final dirs = await createTempDirs('dayseven_my_test');
///   temp = dirs.temp;
///   support = dirs.support;
/// });
/// // No tearDown needed — [createTempDirs] registers cleanup via [addTearDown].
/// ```
library;

import 'dart:io';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

/// Creates two temporary directories and mocks `path_provider` so
/// `getApplicationSupportDirectory()` returns [support.path].
///
/// The mock and both directories are cleaned up automatically via
/// [addTearDown], so callers do not need their own `tearDown`.
///
/// Returns a record `({Directory temp, Directory support})`.
Future<({Directory temp, Directory support})> createTempDirs(
  String prefix,
) async {
  final temp = await Directory.systemTemp.createTemp(prefix);
  final support = await Directory.systemTemp.createTemp('${prefix}_support');

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
    if (call.method == 'getApplicationSupportDirectory') {
      return support.path;
    }
    return null;
  });

  addTearDown(() async {
    await clearTempMocks();
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await support.exists()) await support.delete(recursive: true);
  });

  return (temp: temp, support: support);
}

/// Removes the `path_provider` mock handler.
///
/// Also registered automatically by [createTempDirs]; call it explicitly only
/// when you mocked outside the harness.
Future<void> clearTempMocks() async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, null);
}

/// Opens a Knowledge Base at [temp.path] and returns the container and its
/// [KnowledgeBase].
///
/// The container is registered with [addTearDown] so it is disposed after the
/// test. The open is performed inside [WidgetTester.runAsync] so real async
/// I/O is not masked by fake async.
Future<(ProviderContainer container, KnowledgeBase kb)> openTestKb(
  WidgetTester tester,
  Directory temp, {
  String name = 'MyWorld',
  List<Override> overrides = const [],
}) async {
  final container = ProviderContainer(overrides: overrides);
  addTearDown(container.dispose);

  await tester.runAsync(() async {
    await container
        .read(kbControllerProvider.notifier)
        .openFolder(temp.path, createWithName: name);
  });

  final kb = container.read(kbSessionProvider)!.kb;
  return (container, kb);
}

/// Opens a Knowledge Base and seeds typical content used by appearance / shell
/// tests.
///
/// Creates:
/// - `Characters/`
/// - `Characters/Houses/`
/// - `Places/`
/// - Document `Aldric` in `Characters/`
/// - Document `House Vane` in `Characters/Houses/`
/// - Document `Aldenmoor` in `Places/`
/// - Document `Timeline` at the root with a single paragraph block.
///
/// The container is registered with [addTearDown] so it is disposed after the
/// test. Refreshes the tree before returning.
Future<ProviderContainer> seededKbContainer(
  WidgetTester tester,
  Directory temp, {
  String name = 'MyWorld',
  List<Override> overrides = const [],
}) async {
  final (container, kb) = await openTestKb(
    tester,
    temp,
    name: name,
    overrides: overrides,
  );

  await tester.runAsync(() async {
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
