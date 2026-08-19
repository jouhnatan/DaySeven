import 'dart:io';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_search_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('search index', () {
    test('finds documents by body text, live on a partial word', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      final path = await kb.createDocument(title: 'Aldenmoor');
      final doc = await kb.readDocument(path);
      await kb.writeDocument(
        path,
        doc.copyWith(
          blocks: [
            ParagraphBlock(
              id: newId(),
              spans: const [
                TextSpanNode(
                  text: 'The fen swallows the old road each autumn.',
                ),
              ],
            ),
          ],
        ),
      );

      final index = await SearchIndex.openFor(kb);
      addTearDown(index.close);
      await index.rebuild();

      // A partial word, as the user would have typed it so far.
      final hits = index.search('swall');
      expect(hits, hasLength(1));
      expect(hits.single.relativePath, path);
      expect(hits.single.snippet, contains('swallows'));

      expect(
        index.search('Aldenmoor'),
        hasLength(1),
        reason: 'titles are indexed too',
      );
      expect(index.search('nothinghere'), isEmpty);
    });

    test('upsert reflects an edit without a full rebuild', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      final path = await kb.createDocument(title: 'Aldenmoor');
      final index = await SearchIndex.openFor(kb);
      addTearDown(index.close);
      await index.rebuild();

      final doc = await kb.readDocument(path);
      final edited = doc.copyWith(
        blocks: [
          ParagraphBlock(
            id: newId(),
            spans: const [
              TextSpanNode(text: 'A lantern burns at the causeway.'),
            ],
          ),
        ],
      );
      await kb.writeDocument(path, edited);
      index.upsert(path, edited);

      expect(index.search('lantern'), hasLength(1));
      expect(index.search('causeway'), hasLength(1));
    });

    test(
      'a query of only punctuation returns nothing rather than throwing',
      () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final index = await SearchIndex.openFor(kb);
        addTearDown(index.close);
        await index.rebuild();

        expect(index.search('   '), isEmpty);
        expect(index.search('"*^'), isEmpty);
      },
    );
  });
}
