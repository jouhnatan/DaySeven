import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

void main() {
  late Directory temp;
  late KnowledgeBase kb;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_sync_ledger');
    kb = await KnowledgeBase.create(folder: temp.path, name: 'Shared KB');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test(
    'persists the exact revision, hash and path used as a sync base',
    () async {
      final document = BlockDocument(
        id: 'document-1',
        title: 'Chapter',
        blocks: const [ParagraphBlock(id: 'paragraph-1', spans: [])],
      );
      final ledger = await SyncLedger.open(kb);

      await ledger.record(
        document: document,
        revisionId: 'revision-1',
        path: 'Drafts/Chapter.md',
      );

      final reopened = await SyncLedger.open(kb);
      expect(reopened.document(document.id)?.revisionId, 'revision-1');
      expect(reopened.document(document.id)?.contentHash, document.contentHash);
      expect(reopened.document(document.id)?.path, 'Drafts/Chapter.md');
    },
  );

  test(
    'persists protection while remaining compatible with old ledgers',
    () async {
      final document = BlockDocument(
        id: 'document-1',
        title: 'Chapter',
        blocks: const [],
      );
      final ledger = await SyncLedger.open(kb);
      const protection = DocumentProtection(
        protectionClass: DocumentProtectionClass.protected,
        minimumPublishRole: MinimumPublishRole.coOwner,
      );
      await ledger.record(
        document: document,
        revisionId: 'revision-1',
        path: 'Chapter.md',
        protection: protection,
      );

      expect(
        (await SyncLedger.open(kb)).document(document.id)?.protection,
        protection,
      );

      await File('${kb.settingsPath}/sync.json').writeAsString(
        '{"version":1,"documents":{"document-1":{'
        '"revisionId":"revision-1","contentHash":"hash",'
        '"path":"Chapter.md"}}}',
      );
      expect(
        (await SyncLedger.open(kb)).document(document.id)?.protection,
        isNull,
      );
    },
  );

  test('removes deleted sync bases and tolerates a damaged ledger', () async {
    final document = BlockDocument(
      id: 'document-1',
      title: 'Chapter',
      blocks: const [],
    );
    final ledger = await SyncLedger.open(kb);
    await ledger.record(
      document: document,
      revisionId: 'revision-1',
      path: 'Chapter.md',
    );
    await ledger.remove(document.id);
    expect((await SyncLedger.open(kb)).document(document.id), isNull);

    await File('${kb.settingsPath}/sync.json').writeAsString('{not json');
    expect((await SyncLedger.open(kb)).documents, isEmpty);
  });
}
