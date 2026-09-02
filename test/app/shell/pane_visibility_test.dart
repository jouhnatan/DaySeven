import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/shell/pane_visibility.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_visibility');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('restores and persists Knowledge Base visibility', () async {
    final store = AppStore(File('${temp.path}/dayseven.json'));
    await store.setPaneVisibility('knowledgeBase', false);
    final container = ProviderContainer(
      overrides: [appStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container.dispose);

    container.read(paneVisibilityProvider);
    await _until(() => !container.read(paneVisibilityProvider).knowledgeBase);

    container
        .read(paneVisibilityProvider.notifier)
        .setKnowledgeBaseVisible(true);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect((await store.paneVisibility())['knowledgeBase'], isTrue);
  });

  test('restores and persists World visibility', () async {
    final store = AppStore(File('${temp.path}/dayseven.json'));
    await store.setPaneVisibility('world', false);
    final container = ProviderContainer(
      overrides: [appStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container.dispose);

    container.read(paneVisibilityProvider);
    await _until(() => !container.read(paneVisibilityProvider).world);

    container.read(paneVisibilityProvider.notifier).setWorldVisible(true);
    await Future<void>.delayed(const Duration(milliseconds: 500));

    expect((await store.paneVisibility())['world'], isTrue);
  });

  test('ignores malformed visibility values', () async {
    final file = File('${temp.path}/dayseven.json');
    await file.writeAsString(
      '{"paneVisibility":{"knowledgeBase":"hidden","other":true}}',
    );
    final store = AppStore(file);

    expect(await store.paneVisibility(), {'other': true});

    final container = ProviderContainer(
      overrides: [appStoreProvider.overrideWith((ref) async => store)],
    );
    addTearDown(container.dispose);
    container.read(paneVisibilityProvider);
    await Future<void>.delayed(Duration.zero);

    expect(container.read(paneVisibilityProvider).knowledgeBase, isTrue);
  });
}

Future<void> _until(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not reached');
}
