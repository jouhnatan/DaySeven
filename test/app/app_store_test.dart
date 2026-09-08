import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('concurrent updates are serialized without losing settings', () async {
    final directory = Directory.systemTemp.createTempSync(
      'dayseven_app_store_test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final store = await AppStore.openIn(directory);

    await Future.wait([
      store.noteDocumentOpened('kb-1', 'Places/Aldenmoor.md'),
      store.noteDocumentOpened('kb-1', 'People/Ammur-ili.md'),
      store.setPaneWidth('worldSettings', 280),
      store.setPaneVisibility('right', false),
    ]);

    expect(
      await store.recentDocuments('kb-1'),
      containsAll(['Places/Aldenmoor.md', 'People/Ammur-ili.md']),
    );
    expect(await store.paneWidths(), containsPair('worldSettings', 280));
    expect(await store.paneVisibility(), containsPair('right', false));
  });

  test('opening recovers an interrupted Windows replacement backup', () async {
    final directory = Directory.systemTemp.createTempSync(
      'dayseven_app_store_recovery_test',
    );
    addTearDown(() => directory.deleteSync(recursive: true));
    final backup = File('${directory.path}/dayseven.json.backup');
    await backup.writeAsString('{"recentKbPaths":["/recovered"]}');

    final store = await AppStore.openIn(directory);

    expect(await store.recentKbPaths(), ['/recovered']);
    expect(backup.existsSync(), isFalse);
  });
}
