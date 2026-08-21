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

    test('uses the Markdown file name instead of its embedded title', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      final path = await kb.createDocument(title: 'Aldric');
      final document = await kb.readDocument(path);
      await kb.writeDocument(
        path,
        document.copyWith(title: 'An Outdated Embedded Title'),
      );

      final index = await SearchIndex.openFor(kb);
      addTearDown(index.close);
      await index.rebuild();

      final hits = index.search('Aldric');
      expect(hits, hasLength(1));
      expect(hits.single.relativePath, 'Aldric.md');
      expect(hits.single.title, 'Aldric');
      expect(index.search('Outdated'), isEmpty);
    });

    test('updates the searchable title when a file is renamed', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      final path = await kb.createDocument(title: 'Aldric');
      final index = await SearchIndex.openFor(kb);
      addTearDown(index.close);
      await index.rebuild();

      index.rename(path, 'Characters/The Gatekeeper.md');

      expect(index.search('Aldric'), isEmpty);
      final hits = index.search('Gatekeeper');
      expect(hits, hasLength(1));
      expect(hits.single.relativePath, 'Characters/The Gatekeeper.md');
      expect(hits.single.title, 'The Gatekeeper');
    });

    test('honours a bounded result limit without binding an integer', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      for (var i = 0; i < 3; i++) {
        final path = await kb.createDocument(title: 'Causeway $i');
        final doc = await kb.readDocument(path);
        await kb.writeDocument(
          path,
          doc.copyWith(
            blocks: [
              ParagraphBlock(
                id: newId(),
                spans: const [TextSpanNode(text: 'The causeway remains.')],
              ),
            ],
          ),
        );
      }

      final index = await SearchIndex.openFor(kb);
      addTearDown(index.close);
      await index.rebuild();

      expect(index.search('causeway', limit: 2), hasLength(2));
      expect(index.search('causeway', limit: 0), hasLength(1));
      expect(index.search('causeway', limit: 1000), hasLength(3));
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
