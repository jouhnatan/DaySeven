/// The wash behind the focused paragraph must fade only in alpha.
///
/// Fading to `Colors.transparent` — which is transparent *black* — animates the
/// red, green and blue channels down towards zero as well, and that shows up as
/// a grey flash across the block on every click. This checks the midpoint of
/// the fade rather than its endpoints, because both endpoints looked correct
/// while the bug was live.
library;

import 'dart:io';

import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_test.dart' show openEditor, seedWith;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_wash');
    support = await Directory.systemTemp.createTemp('dayseven_wash_support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : null,
        );
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await support.exists()) await support.delete(recursive: true);
  });

  for (final (name, brightness, ds) in [
    ('light', Brightness.light, DsColors.light),
    ('dark', Brightness.dark, DsColors.dark),
  ]) {
    testWidgets('the wash stays on-hue while fading in, $name', (tester) async {
      final (container, _, _) = await openEditor(
        tester,
        temp,
        seed: seedWith('The second age did not end quietly.'),
        brightness: brightness,
      );

      await tester.tap(find.byType(TextField).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      final mid = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(AnimatedContainer),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((box) => (box.decoration as BoxDecoration).color)
          .whereType<Color>()
          .where((color) => color.a > 0.01 && color.a < 0.99)
          .toList();

      expect(mid, isNotEmpty, reason: 'expected a fade still in progress');

      for (final color in mid) {
        expect(
          (color.r, color.g, color.b),
          (ds.editingBlock.r, ds.editingBlock.g, ds.editingBlock.b),
          reason: 'the wash drifted off-hue mid-fade, which reads as grey',
        );
      }

      // Let the fade finish, then settle the debounced save the tap starts;
      // either one left running is a pending timer at teardown.
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => container.read(documentControllerProvider.notifier).flush(),
      );
    });
  }
}
