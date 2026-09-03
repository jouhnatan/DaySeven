import 'dart:io';

import 'package:dayseven/features/world/data/png_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_png_reader_test');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> writePng(List<int> bytes, {String name = 'sample.png'}) async {
    final file = File(p.join(temp.path, name));
    await file.writeAsBytes(bytes);
    return file;
  }

  test('reads dimensions and greyscale status from a PNG header', () async {
    final file = await writePng(_png(width: 4, height: 2, colourType: 0));

    final metadata = await PngMetadataReader().read(file);

    expect(metadata.width, 4);
    expect(metadata.height, 2);
    expect(metadata.isGreyscale, isTrue);
  });

  test('truecolour PNGs are not greyscale', () async {
    final file = await writePng(_png(width: 4, height: 2, colourType: 2));

    expect((await PngMetadataReader().read(file)).isGreyscale, isFalse);
  });

  test('indexed PNGs are not greyscale', () async {
    final file = await writePng(_png(width: 4, height: 2, colourType: 3));

    expect((await PngMetadataReader().read(file)).isGreyscale, isFalse);
  });

  test('finds tEXt after IDAT', () async {
    final file = await writePng(
      _png(
        chunks: [
          _chunk('IDAT', [1, 2, 3, 4]),
          _chunk('tEXt', [...'planetCode'.codeUnits, 0, ...'aster'.codeUnits]),
        ],
      ),
    );

    final metadata = await PngMetadataReader().read(file);

    expect(metadata.textChunks['planetCode'], 'aster');
    expect(metadata.planetCode, 'aster');
  });

  test('rejects a bad signature', () async {
    final file = await writePng(List<int>.filled(8, 0));

    expect(
      PngMetadataReader().read(file),
      throwsA(isA<PngMetadataException>()),
    );
  });

  test('rejects a truncated file', () async {
    final file = await writePng(_pngSignature);

    expect(
      PngMetadataReader().read(file),
      throwsA(isA<PngMetadataException>()),
    );
  });

  test('rejects a chunk longer than the remaining file', () async {
    final file = await writePng([
      ..._pngSignature,
      ..._uint32(100),
      ...'tEXt'.codeUnits,
      0,
      0,
      0,
      0,
    ]);

    expect(
      PngMetadataReader().read(file),
      throwsA(isA<PngMetadataException>()),
    );
  });

  test('safely reads PNGs with more than 1000 chunks', () async {
    final file = await writePng(
      _png(
        chunks: [
          for (var i = 0; i < 1050; i++) _chunk('IDAT', const []),
        ],
      ),
    );

    final metadata = await PngMetadataReader().read(file);
    expect(metadata.width, 4);
    expect(metadata.height, 2);
  });
}

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

List<int> _png({
  int width = 4,
  int height = 2,
  int colourType = 0,
  List<List<int>> chunks = const [],
}) => [
  ..._pngSignature,
  ..._chunk('IHDR', [
    ..._uint32(width),
    ..._uint32(height),
    8,
    colourType,
    0,
    0,
    0,
  ]),
  ...chunks.expand((chunk) => chunk),
  ..._chunk('IEND', const []),
];

List<int> _chunk(String type, List<int> data) => [
  ..._uint32(data.length),
  ...type.codeUnits,
  ...data,
  0,
  0,
  0,
  0,
];

List<int> _uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];
