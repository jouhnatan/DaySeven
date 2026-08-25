import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Asset paths have to survive being turned into asset keys.
///
/// Flutter percent-encodes an asset path into the manifest key but ships the
/// file under its original name, so a path containing characters that need
/// encoding produces a key that resolves to nothing. For a font that failure
/// is silent: the family just falls back to the default sans, and nothing in
/// the build or the test run says a word.
///
/// This bit once, with the upstream `SpaceGrotesk[wght].ttf`. Variable fonts
/// are commonly published with an axis list in square brackets, so it is worth
/// a guard rather than a memory.
void main() {
  test('every declared asset path needs no escaping', () {
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final declared = <String>[];

    for (final line in pubspec) {
      final trimmed = line.trim();
      final match = RegExp(r'^-\s+(?:asset:\s*)?(assets/\S+)$')
          .firstMatch(trimmed);
      if (match != null) declared.add(match.group(1)!);
    }

    expect(declared, isNotEmpty, reason: 'the pubspec should declare assets');

    for (final path in declared) {
      expect(
        Uri.encodeFull(path),
        path,
        reason:
            '"$path" changes when it becomes an asset key, so the key will '
            'not resolve to the file. Rename it to something URL-safe.',
      );
      expect(
        File(path).existsSync() || Directory(path).existsSync(),
        isTrue,
        reason: '"$path" is declared in pubspec.yaml but is not on disk',
      );
    }
  });
}
