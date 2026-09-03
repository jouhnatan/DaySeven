import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:dayseven/features/world/world_renderer/globe_texture_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('decodes, caches, replaces, and disposes textures', () async {
    final temp = await Directory.systemTemp.createTemp(
      'dayseven_globe_texture_test',
    );
    addTearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    final firstFile = File(p.join(temp.path, 'first.png'))
      ..writeAsBytesSync(_png(width: 4, height: 2));
    final secondFile = File(p.join(temp.path, 'second.png'))
      ..writeAsBytesSync(_png(width: 6, height: 3));
    final loader = GlobeTextureLoader();
    addTearDown(loader.dispose);

    var notifications = 0;
    loader.addListener(() => notifications++);
    await loader.loadAsset(firstFile.path, assetId: 'first.png');

    final firstTexture = loader.texture;
    expect(firstTexture, isNotNull);
    expect(firstTexture!.width, 4);
    expect(loader.currentAssetId, 'first.png');
    expect(loader.isLoading, isFalse);
    final afterFirstLoad = notifications;

    await loader.loadAsset(firstFile.path, assetId: 'first.png');
    expect(loader.texture, same(firstTexture));
    expect(notifications, afterFirstLoad);

    await loader.loadAsset(secondFile.path, assetId: 'second.png');
    expect(loader.currentAssetId, 'second.png');
    expect(loader.texture, isNot(same(firstTexture)));
    expect(loader.texture!.width, 6);

    loader.clear();
    expect(loader.texture, isNull);
    expect(loader.currentAssetId, isNull);
  });
}

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

Uint8List _png({required int width, required int height}) {
  final raw = <int>[];
  for (var row = 0; row < height; row++) {
    raw.add(0);
    raw.addAll(List<int>.filled(width, 0x60));
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
