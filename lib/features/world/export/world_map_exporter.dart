/// Raster export for the source map with explicit output-format control.
library;

import 'dart:typed_data';

import 'package:image/image.dart' as img;

enum WorldMapImageFormat {
  png(extension: 'png', mediaType: 'image/png'),
  jpeg(extension: 'jpg', mediaType: 'image/jpeg');

  const WorldMapImageFormat({required this.extension, required this.mediaType});

  final String extension;
  final String mediaType;
}

class WorldMapExporter {
  const WorldMapExporter();

  Uint8List transcode(
    Uint8List source, {
    required WorldMapImageFormat format,
    int jpegQuality = 92,
  }) {
    final decoded = img.decodeImage(source);
    if (decoded == null) {
      throw const FormatException('The source map is not a valid image.');
    }
    return switch (format) {
      WorldMapImageFormat.png => Uint8List.fromList(img.encodePng(decoded)),
      WorldMapImageFormat.jpeg => Uint8List.fromList(
        img.encodeJpg(decoded, quality: jpegQuality.clamp(1, 100)),
      ),
    };
  }
}
