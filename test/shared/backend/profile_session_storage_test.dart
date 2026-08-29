/// Per-profile session storage: what keeps a second window's account separate.
library;

import 'dart:io';

import 'package:dayseven/shared/backend/profile_session_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dayseven-session-');
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  group('FileLocalStorage', () {
    test('an absent file reads as signed out, not as an error', () async {
      final storage = FileLocalStorage.inDirectory(dir);

      expect(await storage.hasAccessToken(), isFalse);
      expect(await storage.accessToken(), isNull);
    });

    test('a persisted session round-trips', () async {
      final storage = FileLocalStorage.inDirectory(dir);
      await storage.persistSession('{"access_token":"abc"}');

      expect(await storage.hasAccessToken(), isTrue);
      expect(await storage.accessToken(), '{"access_token":"abc"}');
    });

    test('signing out removes it, and asking again is still safe', () async {
      final storage = FileLocalStorage.inDirectory(dir);
      await storage.persistSession('{"access_token":"abc"}');
      await storage.removePersistedSession();

      expect(await storage.hasAccessToken(), isFalse);
      await storage.removePersistedSession();
    });

    test('two profiles hold two different accounts', () async {
      // This is the whole point of the class: one machine, two logins.
      final a = Directory(p.join(dir.path, 'a'))..createSync();
      final b = Directory(p.join(dir.path, 'b'))..createSync();

      await FileLocalStorage.inDirectory(a).persistSession('account-a');
      await FileLocalStorage.inDirectory(b).persistSession('account-b');

      expect(await FileLocalStorage.inDirectory(a).accessToken(), 'account-a');
      expect(await FileLocalStorage.inDirectory(b).accessToken(), 'account-b');
    });

    test('a written session leaves no temporary file behind', () async {
      final storage = FileLocalStorage.inDirectory(dir);
      await storage.persistSession('{"access_token":"abc"}');

      expect(
        dir.listSync().map((e) => p.basename(e.path)),
        isNot(contains(endsWith('.tmp'))),
      );
    });
  });

  group('FileGotrueAsyncStorage', () {
    test('items round-trip and can be removed', () async {
      final storage = FileGotrueAsyncStorage.inDirectory(dir);

      expect(await storage.getItem(key: 'verifier'), isNull);
      await storage.setItem(key: 'verifier', value: 'xyz');
      expect(await storage.getItem(key: 'verifier'), 'xyz');

      await storage.removeItem(key: 'verifier');
      expect(await storage.getItem(key: 'verifier'), isNull);
    });

    test('keeps other keys when one is removed', () async {
      final storage = FileGotrueAsyncStorage.inDirectory(dir);
      await storage.setItem(key: 'one', value: '1');
      await storage.setItem(key: 'two', value: '2');

      await storage.removeItem(key: 'one');

      expect(await storage.getItem(key: 'one'), isNull);
      expect(await storage.getItem(key: 'two'), '2');
    });

    test('a damaged file reads as empty rather than throwing mid-sign-in',
        () async {
      final storage = FileGotrueAsyncStorage.inDirectory(dir);
      await storage.setItem(key: 'verifier', value: 'xyz');
      await storage.file.writeAsString('{ not json');

      expect(await storage.getItem(key: 'verifier'), isNull);
      // And it recovers, rather than staying broken.
      await storage.setItem(key: 'verifier', value: 'new');
      expect(await storage.getItem(key: 'verifier'), 'new');
    });
  });
}
