/// Validates PNG and JPEG World map files and reads their raster dimensions.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/shared/world/data/png_metadata_reader.dart';
import 'package:dayseven/shared/world/domain/world_metadata.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class WorldImageMetadataReader {
  const WorldImageMetadataReader();

  Future<WorldMetadata> read(File file) async {
    final handle = await file.open();
    try {
      final prefix = await handle.read(12);
      if (_isPng(prefix)) {
        return await PngMetadataReader().read(file);
      }
      if (_isJpeg(prefix)) {
        return await _readJpeg(handle);
      }
      throw const KbException('A World map has to be a PNG or JPEG image.');
    } finally {
      await handle.close();
    }
  }

  bool _isPng(Uint8List bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0d &&
      bytes[5] == 0x0a &&
      bytes[6] == 0x1a &&
      bytes[7] == 0x0a;

  bool _isJpeg(Uint8List bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;

  Future<WorldMetadata> _readJpeg(RandomAccessFile handle) async {
    await handle.setPosition(2);
    while (true) {
      final markerPrefix = await handle.readByte();
      if (markerPrefix == -1) break;
      if (markerPrefix != 0xff) continue;

      var marker = await handle.readByte();
      while (marker == 0xff) {
        marker = await handle.readByte();
      }
      if (marker == -1 || marker == 0xd9 || marker == 0xda) break;
      if (marker == 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue;

      final lengthBytes = await handle.read(2);
      if (lengthBytes.length != 2) break;
      final length = lengthBytes[0] << 8 | lengthBytes[1];
      if (length < 2) break;

      if (_isStartOfFrame(marker)) {
        final frame = await handle.read(5);
        if (frame.length != 5) break;
        final height = frame[1] << 8 | frame[2];
        final width = frame[3] << 8 | frame[4];
        if (width <= 0 || height <= 0) break;
        return WorldMetadata(
          width: width,
          height: height,
          isGreyscale: false,
          mediaType: 'image/jpeg',
        );
      }
      await handle.setPosition(await handle.position() + length - 2);
    }
    throw const KbException('That JPEG image is incomplete or invalid.');
  }

  bool _isStartOfFrame(int marker) =>
      marker >= 0xc0 &&
      marker <= 0xcf &&
      marker != 0xc4 &&
      marker != 0xc8 &&
      marker != 0xcc;
}
