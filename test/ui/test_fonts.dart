/// Font loading for tests that render.
///
/// `flutter test` ships neither the bundled Aleo nor the Material icon font, so
/// without this text and icons come out as empty boxes.
library;

import 'dart:io';

import 'package:dayseven/app/theme.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

Future<void> loadTestFonts() async {
  final aleo = FontLoader(kEditorFontFamily);
  for (final path in [
    'assets/fonts/aleo/Aleo.ttf',
    'assets/fonts/aleo/Aleo-Italic.ttf',
  ]) {
    aleo.addFont(File(path).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await aleo.load();

  // Skipped when the SDK cannot be located; icons then render as boxes.
  final flutterRoot = Platform.environment['FLUTTER_ROOT'];
  if (flutterRoot == null) return;
  final icons = File(
    p.join(
      flutterRoot,
      'bin',
      'cache',
      'artifacts',
      'material_fonts',
      'MaterialIcons-Regular.otf',
    ),
  );
  if (!icons.existsSync()) return;

  await (FontLoader(
    'MaterialIcons',
  )..addFont(icons.readAsBytes().then((b) => b.buffer.asByteData()))).load();
}
