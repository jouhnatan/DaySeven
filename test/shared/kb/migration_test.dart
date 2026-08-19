/// Converting a Knowledge Base from the old JSON documents to Markdown.
///
/// This runs across a user's whole library on every open, so the tests here are
/// weighted towards what must *not* happen: nothing deleted, nothing
/// overwritten, and nothing written at all unless it survived a round trip.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/markdown.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_migration');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  BlockDocument sample({String id = 'd1', String text = 'He keeps the way.'}) =>
      BlockDocument(
        id: id,
        title: 'Aldric',
        blocks: [
          HeadingBlock(
            id: 'h1',
            level: 2,
            spans: const [TextSpanNode(text: 'Aldric')],
          ),
          ParagraphBlock(
            id: 'b1',
            spans: [
              TextSpanNode(text: text, bold: true),
              const TextSpanNode(text: ' Always.', underline: true),
            ],
            align: BlockAlign.center,
            spaceBefore: 16,
          ),
        ],
      );

  /// Writes [document] as a legacy JSON file at [relative].
  Future<File> writeLegacy(String relative, BlockDocument document) async {
    final file = File(p.join(temp.path, '$relative$kLegacyDocumentExtension'));
    await file.parent.create(recursive: true);
    await file.writeAsString(document.encode());
    return file;
  }

  Future<KnowledgeBase> makeKb() =>
      KnowledgeBase.create(folder: temp.path, name: 'MyWorld');

  test(
    'a legacy document converts, and the original is kept as a backup',
    () async {
      await makeKb();
      final legacy = await writeLegacy('Characters/Aldric', sample());

      final kb = await KnowledgeBase.open(temp.path);

      final converted = File(p.join(temp.path, 'Characters', 'Aldric.md'));
      expect(converted.existsSync(), isTrue);
      expect(
        legacy.existsSync(),
        isFalse,
        reason: 'renamed, not left in place',
      );
      expect(
        File('${legacy.path}$kConvertedBackupSuffix').existsSync(),
        isTrue,
        reason: 'the original is never deleted',
      );

      final read = await kb.readDocument('Characters/Aldric.md');
      expect(read.sameContentAs(sample()), isTrue);
      expect(read.contentHash, sample().contentHash);
    },
  );

  test('the converted file is Markdown a person would recognise', () async {
    await makeKb();
    await writeLegacy('Aldric', sample());
    await KnowledgeBase.open(temp.path);

    final text = await File(p.join(temp.path, 'Aldric.md')).readAsString();
    expect(text, contains('## Aldric'));
    expect(text, contains('**He keeps the way.**'));
    expect(text, contains('<u> Always.</u>'));
  });

  test('the backup does not show up as a document', () async {
    await makeKb();
    await writeLegacy('Aldric', sample());
    final kb = await KnowledgeBase.open(temp.path);

    final names = (await kb.readTree()).map((n) => n.name).toList();
    expect(names, ['Aldric.md']);
  });

  test('an unparseable document is left exactly as it was', () async {
    await makeKb();
    final broken = File(p.join(temp.path, 'Broken$kLegacyDocumentExtension'));
    await broken.writeAsString('{ this is not json');

    final kb = await KnowledgeBase.open(temp.path);

    expect(broken.existsSync(), isTrue);
    expect(await broken.readAsString(), '{ this is not json');
    expect(File(p.join(temp.path, 'Broken.md')).existsSync(), isFalse);
    expect(
      (await kb.readTree()).map((n) => n.name),
      contains('Broken$kLegacyDocumentExtension'),
      reason: 'still visible, so it cannot silently disappear',
    );
  });

  test(
    'a document that failed to convert stays readable and writable',
    () async {
      await makeKb();
      // A valid document that simply has not been converted yet.
      await writeLegacy('Aldric', sample());
      final kb = await KnowledgeBase.open(temp.path);
      // Put it back to prove the legacy path still round-trips.
      await File(p.join(temp.path, 'Aldric.md')).delete();
      await writeLegacy('Aldric', sample());

      const path = 'Aldric$kLegacyDocumentExtension';
      final edited = sample().copyWith(title: 'Aldric the Younger');
      await kb.writeDocument(path, edited);

      final back = await kb.readDocument(path);
      expect(back.title, 'Aldric the Younger');
      expect(
        await File(p.join(temp.path, path)).readAsString(),
        startsWith('{'),
        reason: 'a legacy file keeps being written as JSON',
      );
    },
  );

  test(
    'an existing Markdown file of the same name is never overwritten',
    () async {
      await makeKb();
      final legacy = await writeLegacy(
        'Aldric',
        sample(text: 'From the JSON.'),
      );

      final rival = File(p.join(temp.path, 'Aldric.md'));
      await rival.writeAsString(
        encodeMarkdown(sample(text: 'From the Markdown.')),
      );

      await KnowledgeBase.open(temp.path);

      expect(
        await rival.readAsString(),
        contains('From the Markdown.'),
        reason: 'the file that was already there wins',
      );
      expect(legacy.existsSync(), isTrue, reason: 'and neither is discarded');
    },
  );

  test('an interrupted run is finished on the next open', () async {
    await makeKb();
    final document = sample();
    final legacy = await writeLegacy('Aldric', document);

    // What a crash between "wrote the .md" and "renamed the original" leaves.
    await File(p.join(temp.path, 'Aldric.md'))
        .writeAsString(encodeMarkdown(document));

    await KnowledgeBase.open(temp.path);

    expect(legacy.existsSync(), isFalse);
    expect(
      File('${legacy.path}$kConvertedBackupSuffix').existsSync(),
      isTrue,
      reason: 'the rename is completed rather than the file being left over',
    );
  });

  test('one bad document does not stop the others converting', () async {
    await makeKb();
    await writeLegacy('Good', sample());
    await File(p.join(temp.path, 'Bad$kLegacyDocumentExtension'))
        .writeAsString('not json at all');
    await writeLegacy('Characters/AlsoGood', sample());

    await KnowledgeBase.open(temp.path);

    expect(File(p.join(temp.path, 'Good.md')).existsSync(), isTrue);
    expect(
      File(p.join(temp.path, 'Characters', 'AlsoGood.md')).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(temp.path, 'Bad$kLegacyDocumentExtension')).existsSync(),
      isTrue,
    );
  });

  test('the app\'s own files under .settings are left alone', () async {
    await makeKb();
    final inSettings = File(
      p.join(temp.path, kSettingsDirName, 'stray$kLegacyDocumentExtension'),
    );
    await inSettings.parent.create(recursive: true);
    await inSettings.writeAsString(sample().encode());

    await KnowledgeBase.open(temp.path);

    expect(inSettings.existsSync(), isTrue);
    expect(
      File(p.join(temp.path, kSettingsDirName, 'stray.md')).existsSync(),
      isFalse,
    );
  });

  test('the manifest records the new bundle version', () async {
    await makeKb();
    final manifestFile = File(
      p.join(temp.path, kSettingsDirName, kManifestFileName),
    );

    // Put the manifest back to the old version, as an existing bundle would be.
    final json =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    json['schemaVersion'] = 1;
    await manifestFile.writeAsString(jsonEncode(json));

    final kb = await KnowledgeBase.open(temp.path);
    expect(kb.manifest.schemaVersion, kBundleSchemaVersion);

    final onDisk =
        jsonDecode(await manifestFile.readAsString()) as Map<String, Object?>;
    expect(onDisk['schemaVersion'], kBundleSchemaVersion);
  });

  test('opening twice is a no-op the second time', () async {
    await makeKb();
    await writeLegacy('Aldric', sample());

    await KnowledgeBase.open(temp.path);
    final afterFirst =
        Directory(temp.path)
            .listSync(recursive: true)
            .map((e) => p.relative(e.path, from: temp.path))
            .toList()
          ..sort();

    await KnowledgeBase.open(temp.path);
    final afterSecond =
        Directory(temp.path)
            .listSync(recursive: true)
            .map((e) => p.relative(e.path, from: temp.path))
            .toList()
          ..sort();

    expect(afterSecond, afterFirst, reason: 'no .bak.bak, nothing rewritten');
  });

  test('new documents are created as Markdown', () async {
    final kb = await makeKb();
    final path = await kb.createDocument(title: 'Fresh');

    expect(path, 'Fresh.md');
    expect(
      await File(p.join(temp.path, path)).readAsString(),
      startsWith('---'),
    );
  });
}
