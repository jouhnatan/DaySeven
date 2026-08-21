import 'dart:io';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_kb_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  group('Knowledge Base bundle', () {
    test(
      'create leaves the chosen folder empty apart from .settings',
      () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );

        final settings = p.join(temp.path, kSettingsDirName);
        expect(File(p.join(settings, kManifestFileName)).existsSync(), isTrue);
        expect(Directory(kb.assetsPath).existsSync(), isTrue);
        expect(Directory(kb.indexPath).existsSync(), isTrue);
        expect(kb.manifest.name, 'MyWorld');

        final topLevel = Directory(temp.path)
            .listSync()
            .map((e) => p.basename(e.path))
            .toList();
        expect(topLevel, [
          kSettingsDirName,
        ], reason: 'no scaffolding the user did not ask for');
      },
    );

    test("the user's folders sit directly in the chosen folder", () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      await kb.createFolder('Characters');

      expect(
        Directory(p.join(temp.path, 'Characters')).existsSync(),
        isTrue,
        reason: 'Characters/ is a plain folder in the Knowledge Base',
      );

      final path = await kb.createDocument(
        title: 'Aldric',
        folderRelativePath: 'Characters',
      );
      expect(path, 'Characters/Aldric$kDocumentExtension');
      expect(
        File(p.join(temp.path, 'Characters', 'Aldric$kDocumentExtension'))
            .existsSync(),
        isTrue,
      );
    });

    test('a folder made outside the app shows up in the tree', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');

      // As if created in Finder or Explorer.
      await Directory(p.join(temp.path, 'Characters')).create();

      final tree = await kb.readTree();
      expect(tree.map((n) => n.name), ['Characters']);
    });

    test('.settings never appears in the tree', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      await kb.createFolder('Places');

      final tree = await kb.readTree();
      expect(tree.map((n) => n.name), ['Places']);
    });

    test('a Knowledge Base in the old flat layout migrates on open', () async {
      // Everything at the top of the folder, as the first layout had it.
      final documents = Directory(p.join(temp.path, kDocumentsDirName));
      await Directory(p.join(documents.path, 'Characters'))
          .create(recursive: true);
      await Directory(p.join(temp.path, kAssetsDirName))
          .create(recursive: true);
      await File(p.join(temp.path, kManifestFileName)).writeAsString(
        '{"schemaVersion":1,"kbId":"kb-1","name":"MyWorld",'
        '"createdAt":"2026-01-01T00:00:00.000Z"}',
      );
      await File(p.join(documents.path, 'Aldenmoor$kDocumentExtension'))
          .writeAsString(
            '{"schemaVersion":1,"id":"d1","title":"Aldenmoor","blocks":[]}',
          );

      final kb = await KnowledgeBase.open(temp.path);

      expect(kb.manifest.kbId, 'kb-1', reason: 'the identity is preserved');
      expect(documents.existsSync(), isFalse);
      expect(File(p.join(temp.path, kManifestFileName)).existsSync(), isFalse);
      expect(Directory(kb.assetsPath).existsSync(), isTrue);

      final tree = await kb.readTree();
      expect(tree.map((n) => n.name), [
        'Characters',
        'Aldenmoor$kDocumentExtension',
      ]);
    });

    test(
      'a Knowledge Base with documents under .settings migrates on open',
      () async {
        // The intermediate layout: documents nested inside .settings.
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final nested = Directory(
          p.join(temp.path, kSettingsDirName, kDocumentsDirName, 'Characters'),
        );
        await nested.create(recursive: true);
        await File(p.join(nested.path, 'Aldric$kDocumentExtension'))
            .writeAsString(
              '{"schemaVersion":1,"id":"d1","title":"Aldric","blocks":[]}',
            );

        final reopened = await KnowledgeBase.open(temp.path);

        expect(reopened.manifest.kbId, kb.manifest.kbId);
        expect(
          Directory(p.join(temp.path, kSettingsDirName, kDocumentsDirName))
              .existsSync(),
          isFalse,
        );

        final tree = await reopened.readTree();
        final characters = tree.single as KbFolder;
        expect(characters.name, 'Characters');
        expect(
          characters.children.single.relativePath,
          'Characters/Aldric$kDocumentExtension',
        );
      },
    );

    test(
      'refuses to create a second Knowledge Base in the same folder',
      () async {
        await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
        expect(
          () => KnowledgeBase.create(folder: temp.path, name: 'Another'),
          throwsA(isA<KbException>()),
        );
      },
    );

    test('reopening finds the same kb id', () async {
      final created = await KnowledgeBase.create(
        folder: temp.path,
        name: 'MyWorld',
      );
      final reopened = await KnowledgeBase.open(temp.path);
      expect(reopened.manifest.kbId, created.manifest.kbId);
    });

    test('open repairs derived folders the user deleted', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      await Directory(kb.indexPath).delete(recursive: true);

      final reopened = await KnowledgeBase.open(temp.path);
      expect(Directory(reopened.indexPath).existsSync(), isTrue);
    });

    test('documents round-trip through the folder', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      await kb.createFolder('Places');
      final path = await kb.createDocument(
        title: 'Aldenmoor',
        folderRelativePath: 'Places',
      );

      expect(path, 'Places/Aldenmoor.md');

      final doc = await kb.readDocument(path);
      final edited = doc.copyWith(
        blocks: [
          ParagraphBlock(
            id: newId(),
            spans: const [TextSpanNode(text: 'Fog sits low over the fen.')],
          ),
        ],
      );
      await kb.writeDocument(path, edited);

      final reread = await kb.readDocument(path);
      expect(reread.plainText, 'Fog sits low over the fen.');
      expect(reread.sameContentAs(edited), isTrue);
    });

    test(
      'a title with path separators cannot escape the documents folder',
      () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final path = await kb.createDocument(title: '../../etc/passwd');

        expect(path, contains('etcpasswd'));
        expect(p.isWithin(kb.documentsPath, kb.absolutePathFor(path)), isTrue);
      },
    );

    test('folders can be created and nested', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');

      await kb.createFolder('Places');
      await kb.createFolder('Places/Coastal');
      await kb.createDocument(
        title: 'Aldenmoor',
        folderRelativePath: 'Places/Coastal',
      );

      final tree = await kb.readTree();
      final places = tree.single as KbFolder;
      expect(places.name, 'Places');

      final coastal = places.children.single as KbFolder;
      expect(coastal.name, 'Coastal');
      expect(
        coastal.children.single.relativePath,
        'Places/Coastal/Aldenmoor$kDocumentExtension',
      );
    });

    group('renaming documents', () {
      test('renames the Markdown file and its embedded title', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters');
        final path = await kb.createDocument(
          title: 'Aldric',
          folderRelativePath: 'Characters',
        );
        final before = await kb.readDocument(path);
        await kb.writeDocument(
          path,
          before.copyWith(
            blocks: [
              ParagraphBlock(
                id: newId(),
                spans: const [TextSpanNode(text: 'He keeps the causeway.')],
              ),
            ],
          ),
        );

        final renamed = await kb.renameDocument(path, 'The Gatekeeper.md');

        expect(renamed, 'Characters/The Gatekeeper.md');
        expect(File(kb.absolutePathFor(path)).existsSync(), isFalse);
        expect(File(kb.absolutePathFor(renamed)).existsSync(), isTrue);
        final after = await kb.readDocument(renamed);
        expect(after.id, before.id);
        expect(after.title, 'The Gatekeeper');
        expect(after.plainText, 'He keeps the causeway.');
      });

      test('refuses to overwrite another document', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final aldric = await kb.createDocument(title: 'Aldric');
        final bryn = await kb.createDocument(title: 'Bryn');

        expect(
          () => kb.renameDocument(aldric, 'Bryn'),
          throwsA(isA<KbException>()),
        );
        expect(File(kb.absolutePathFor(aldric)).existsSync(), isTrue);
        expect(File(kb.absolutePathFor(bryn)).existsSync(), isTrue);
      });

      test('avoids Windows reserved device names', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final path = await kb.createDocument(title: 'Aldric');

        final renamed = await kb.renameDocument(path, 'CON');

        expect(renamed, '_CON.md');
        expect((await kb.readDocument(renamed)).title, '_CON');
      });
    });

    group('moving things about', () {
      test('a document moves into a folder', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters');
        final path = await kb.createDocument(title: 'Aldric');

        final moved = await kb.move(path, 'Characters');

        expect(moved, 'Characters/Aldric$kDocumentExtension');
        expect(File(kb.absolutePathFor(moved)).existsSync(), isTrue);
        expect(File(kb.absolutePathFor(path)).existsSync(), isFalse);
      });

      test('a document moves back out to the top level', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters');
        final path = await kb.createDocument(
          title: 'Aldric',
          folderRelativePath: 'Characters',
        );

        final moved = await kb.move(path, '');

        expect(moved, 'Aldric$kDocumentExtension');
        expect(File(kb.absolutePathFor(moved)).existsSync(), isTrue);
      });

      test('a folder moves with everything inside it', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Houses');
        await kb.createDocument(title: 'Vane', folderRelativePath: 'Houses');
        await kb.createFolder('Characters');

        final moved = await kb.move('Houses', 'Characters');

        expect(moved, 'Characters/Houses');
        expect(
          File(kb.absolutePathFor('Characters/Houses/Vane$kDocumentExtension'))
              .existsSync(),
          isTrue,
        );
      });

      test('a folder cannot be dropped inside itself', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters');
        await kb.createFolder('Characters/Houses');

        expect(
          () => kb.move('Characters', 'Characters/Houses'),
          throwsA(isA<KbException>()),
        );
        expect(
          () => kb.move('Characters', 'Characters'),
          throwsA(isA<KbException>()),
        );
      });

      test('a move that would overwrite something is refused', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters');
        final path = await kb.createDocument(title: 'Aldric');
        await kb.createDocument(
          title: 'Aldric',
          folderRelativePath: 'Characters',
        );

        expect(() => kb.move(path, 'Characters'), throwsA(isA<KbException>()));
        expect(
          File(kb.absolutePathFor(path)).existsSync(),
          isTrue,
          reason: 'the document stays where it was',
        );
      });

      test('moving into the folder it is already in changes nothing', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters');
        final path = await kb.createDocument(
          title: 'Aldric',
          folderRelativePath: 'Characters',
        );

        expect(await kb.move(path, 'Characters'), path);
      });
    });

    group('deleting items', () {
      test('deletes a document', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final path = await kb.createDocument(title: 'Aldric');

        await kb.deleteNode(path);

        expect(File(kb.absolutePathFor(path)).existsSync(), isFalse);
      });

      test('deletes a folder and everything below it', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        await kb.createFolder('Characters/Houses');
        await kb.createDocument(
          title: 'Vane',
          folderRelativePath: 'Characters/Houses',
        );

        await kb.deleteNode('Characters');

        expect(
          Directory(kb.absolutePathFor('Characters')).existsSync(),
          isFalse,
        );
      });

      test('refuses root, settings, traversal, and absolute paths', () async {
        final kb = await KnowledgeBase.create(
          folder: temp.path,
          name: 'MyWorld',
        );
        final path = await kb.createDocument(title: 'Aldric');
        final unsafe = <String>[
          '',
          '.',
          '../outside',
          'Characters/../Aldric.md',
          kSettingsDirName,
          '$kSettingsDirName/$kManifestFileName',
          '/tmp/outside',
          r'C:\Users\outside',
        ];

        for (final candidate in unsafe) {
          expect(
            () => kb.deleteNode(candidate),
            throwsA(isA<KbException>()),
            reason: 'must reject $candidate',
          );
        }
        expect(File(kb.manifestPath).existsSync(), isTrue);
        expect(File(kb.absolutePathFor(path)).existsSync(), isTrue);
      });
    });

    test('the tree lists folders before files, each sorted by name', () async {
      final kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
      await kb.createDocument(title: 'Zephyr');
      await kb.createDocument(title: 'Aldenmoor');
      await kb.createFolder('People');

      final tree = await kb.readTree();
      expect(tree.map((n) => n.name), ['People', 'Aldenmoor.md', 'Zephyr.md']);
    });
  });
}
