/// Font loading for tests that render.
///
/// `flutter test` does not automatically load the bundled application fonts or
/// the Material icon font, so without this text and icons render incorrectly.
library;

import 'dart:io';

import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

Future<void> loadTestFonts() async {
  final ibmPlexSans = FontLoader(kDefaultFontFamily);
  for (final path in [
    'assets/fonts/ibm_plex_sans/IBMPlexSans-Light.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-LightItalic.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-Regular.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-Italic.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-Medium.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-MediumItalic.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-SemiBold.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-SemiBoldItalic.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-Bold.ttf',
    'assets/fonts/ibm_plex_sans/IBMPlexSans-BoldItalic.ttf',
  ]) {
    ibmPlexSans.addFont(
      File(path).readAsBytes().then((b) => b.buffer.asByteData()),
    );
  }
  await ibmPlexSans.load();

  final archivo = FontLoader('Archivo');
  for (final path in [
    'assets/fonts/archivo/Archivo.ttf',
    'assets/fonts/archivo/Archivo-Italic.ttf',
  ]) {
    archivo.addFont(
      File(path).readAsBytes().then((b) => b.buffer.asByteData()),
    );
  }
  await archivo.load();

  final geistPixel = FontLoader(kUiHeaderFontFamily)
    ..addFont(
      File('assets/fonts/geist_pixel/GeistPixel-Square.ttf')
          .readAsBytes()
          .then((b) => b.buffer.asByteData()),
    );
  await geistPixel.load();

  // The three families the App settings dialog uses. They belong to that one
  // dialog rather than to the theme, but a golden of it renders in fallback
  // fonts without them.
  final solway = FontLoader('Solway');
  for (final path in [
    'assets/fonts/solway/Solway-Regular.ttf',
    'assets/fonts/solway/Solway-Medium.ttf',
    'assets/fonts/solway/Solway-Bold.ttf',
    'assets/fonts/solway/Solway-ExtraBold.ttf',
  ]) {
    solway.addFont(File(path).readAsBytes().then((b) => b.buffer.asByteData()));
  }
  await solway.load();

  final spaceGrotesk = FontLoader('Space Grotesk')
    ..addFont(
      File('assets/fonts/space_grotesk/SpaceGrotesk-Variable.ttf')
          .readAsBytes()
          .then((b) => b.buffer.asByteData()),
    );
  await spaceGrotesk.load();

  final raleway = FontLoader('Raleway')
    ..addFont(
      File('assets/fonts/raleway/Raleway-Variable.ttf')
          .readAsBytes()
          .then((b) => b.buffer.asByteData()),
    );
  await raleway.load();

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
