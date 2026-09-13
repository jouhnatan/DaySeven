import 'dart:io';

import 'package:dayseven/shared/world/data/world_image_metadata_reader.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads JPEG dimensions from encoded content', () async {
    final directory = await Directory.systemTemp.createTemp('world_jpeg_test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/map.jpg');
    await file.writeAsBytes([
      0xff, 0xd8, // SOI
      0xff, 0xc0, // baseline SOF
      0x00, 0x08, // segment length
      0x08, // precision
      0x04, 0x00, // height 1024
      0x08, 0x00, // width 2048
      0x01, // component count
      0xff, 0xd9, // EOI
    ]);

    final metadata = await const WorldImageMetadataReader().read(file);

    expect(metadata.width, 2048);
    expect(metadata.height, 1024);
    expect(metadata.mediaType, 'image/jpeg');
    expect(metadata.isEquirectangular, isTrue);
  });

  test('rejects extension spoofing', () async {
    final directory = await Directory.systemTemp.createTemp('world_image_test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/not-an-image.png');
    await file.writeAsString('not an image');

    expect(
      () => const WorldImageMetadataReader().read(file),
      throwsA(isA<Exception>()),
    );
  });
}
