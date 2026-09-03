import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dayseven/features/world/world_renderer/world_image_decoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('globe textures downsample an oversized source', () async {
    final image = await WorldImageDecoder.decode(
      _png(width: 3000, height: 4),
      target: WorldImageDecodeTarget.globeTexture,
    );
    addTearDown(image.dispose);

    expect(image.width, 2048);
    expect(image.width, lessThanOrEqualTo(2048));
  });

  test('globe textures do not upscale a narrow source', () async {
    final image = await WorldImageDecoder.decode(
      _png(width: 512, height: 4),
      target: WorldImageDecodeTarget.globeTexture,
    );
    addTearDown(image.dispose);

    expect(image.width, 512);
    expect(image.width, lessThanOrEqualTo(2048));
  });

  test('analysis images use the smaller cap', () async {
    final image = await WorldImageDecoder.decode(
      _png(width: 1024, height: 4),
      target: WorldImageDecodeTarget.analysis,
    );
    addTearDown(image.dispose);

    expect(image.width, 256);
    expect(image.width, lessThanOrEqualTo(256));
  });
}

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

Uint8List _png({required int width, required int height}) {
  final raw = <int>[];
  for (var row = 0; row < height; row++) {
    raw.add(0);
    raw.addAll(List<int>.filled(width, 0x40));
  }
  return Uint8List.fromList([
    ..._pngSignature,
    ..._chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 0, 0, 0, 0]),
    ..._chunk('IDAT', const ZLibEncoder().encode(raw)),
    ..._chunk('IEND', const []),
  ]);
}

List<int> _chunk(String type, List<int> data) {
  final crcInput = [...type.codeUnits, ...data];
  return [..._uint32(data.length), ...crcInput, ..._uint32(_crc32(crcInput))];
}

List<int> _uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc ^= byte;
    for (var bit = 0; bit < 8; bit++) {
      crc = (crc & 1) == 0 ? crc >> 1 : (crc >> 1) ^ 0xedb88320;
    }
  }
  return (~crc) & 0xffffffff;
}
