/// Object files in a Knowledge Base: how they are listed, and — just as
/// importantly — where they are *not* listed.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late KnowledgeBase kb;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_objects_test');
    kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Map<String, Object?> seed(String title) => {
    'kind': 'timeline',
    'version': 1,
    'id': title,
    'title': title,
    'items': const <Object?>[],
  };

  group('listing', () {
    test('readObjects finds object files and no documents', () async {
      await kb.createDocument(title: 'Aldric');
      await kb.createObject(name: 'Third Age', seed: seed('Third Age'));
      await kb.createFolder('Ages');
      await kb.createObject(
        name: 'Fourth Age',
        seed: seed('Fourth Age'),
        folderRelativePath: 'Ages',
      );

      final objects = await kb.readObjects();

      expect(objects.map((f) => f.relativePath), [
        'Ages/Fourth Age.unearth',
        'Third Age.unearth',
      ]);
    });

    test('the document tree does not list objects', () async {
      await kb.createDocument(title: 'Aldric');
      await kb.createObject(name: 'Third Age', seed: seed('Third Age'));

      final paths = documentPathsIn(await kb.readTree()).toList();

      // This is the regression that would corrupt sync: everything downstream
      // of documentPathsIn reads each path as Markdown.
      expect(paths, ['Aldric.md']);
      expect(paths.any(isObjectPath), isFalse);
    });

    test('objects the app keeps for itself are not listed', () async {
      final hidden = Directory(p.join(kb.documentsPath, kSettingsDirName));
      await hidden.create(recursive: true);
      await File(
        p.join(hidden.path, 'internal.unearth'),
      ).writeAsString(jsonEncode(seed('internal')));

      expect(await kb.readObjects(), isEmpty);
    });
  });

  group('writing', () {
    test('an object round-trips through the disk', () async {
      final path = await kb.createObject(
        name: 'Third Age',
        seed: seed('Third Age'),
      );

      expect(path, 'Third Age.unearth');
      expect(await kb.readObjectJson(path), seed('Third Age'));
    });

    test('the file on disk is readable JSON', () async {
      final path = await kb.createObject(
        name: 'Third Age',
        seed: seed('Third Age'),
      );
      final source = await File(kb.absolutePathFor(path)).readAsString();

      expect(source, contains('\n  "kind": "timeline"'));
    });

    test('creating twice gives two objects rather than an error', () async {
      final first = await kb.createObject(name: 'Timeline', seed: seed('a'));
      final second = await kb.createObject(name: 'Timeline', seed: seed('b'));

      expect(first, 'Timeline.unearth');
      expect(second, 'Timeline 2.unearth');
    });

    test('a write leaves no temporary file behind', () async {
      await kb.createObject(name: 'Third Age', seed: seed('Third Age'));

      final names = Directory(
        kb.documentsPath,
      ).listSync().map((e) => p.basename(e.path));
      expect(names.any((n) => n.endsWith('.tmp')), isFalse);
    });

    test('a file that is not a JSON object is refused clearly', () async {
      final path = 'Broken$kObjectExtension';
      await File(kb.absolutePathFor(path)).writeAsString('[1, 2, 3]');

      expect(
        () => kb.readObjectJson(path),
        throwsA(isA<KbException>()),
      );
    });
  });

  group('renaming', () {
    test('an object is renamed within its folder', () async {
      await kb.createFolder('Ages');
      final path = await kb.createObject(
        name: 'Third Age',
        seed: seed('Third Age'),
        folderRelativePath: 'Ages',
      );

      final destination = await kb.renameObject(path, 'Fourth Age');

      expect(destination, 'Ages/Fourth Age.unearth');
      expect(File(kb.absolutePathFor(path)).existsSync(), isFalse);
      expect(await kb.readObjectJson(destination), seed('Third Age'));
    });

    test('renaming onto an existing object is refused', () async {
      final path = await kb.createObject(name: 'Third Age', seed: seed('a'));
      await kb.createObject(name: 'Fourth Age', seed: seed('b'));

      expect(
        () => kb.renameObject(path, 'Fourth Age'),
        throwsA(isA<KbException>()),
      );
    });

    test('a document cannot be renamed through the object path', () async {
      final path = await kb.createDocument(title: 'Aldric');

      expect(
        () => kb.renameObject(path, 'Bregan'),
        throwsA(isA<KbException>()),
      );
    });
  });
}
