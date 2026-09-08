import 'dart:typed_data';

import 'package:dayseven/features/world/export/world_map_exporter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

void main() {
  final source = Uint8List.fromList(
    img.encodePng(img.Image(width: 4, height: 2)),
  );

  test('exports PNG bytes when PNG is selected', () {
    final bytes = const WorldMapExporter().transcode(
      source,
      format: WorldMapImageFormat.png,
    );
    expect(bytes.sublist(0, 8), [
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
  });

  test('exports JPEG bytes when JPEG is selected', () {
    final bytes = const WorldMapExporter().transcode(
      source,
      format: WorldMapImageFormat.jpeg,
    );
    expect(bytes.sublist(0, 3), [0xff, 0xd8, 0xff]);
  });
}
