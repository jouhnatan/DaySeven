/// The World feature's only gateway for turning encoded image bytes into a
/// bounded raster image.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// The bounded raster size needed by a particular World operation.
enum WorldImageDecodeTarget {
  /// Texture detail for the globe renderer.
  globeTexture(maxWidth: 2048),

  /// Small detail for analysis such as classification or histograms.
  analysis(maxWidth: 256);

  const WorldImageDecodeTarget({required this.maxWidth});

  final int maxWidth;
}

/// Decodes World images without allowing an unconstrained raster allocation.
abstract final class WorldImageDecoder {
  /// Decodes [bytes] at the smaller of the source width and [target]'s cap.
  static Future<ui.Image> decode(
    Uint8List bytes, {
    required WorldImageDecodeTarget target,
  }) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    ui.Codec? codec;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      final effectiveWidth = math.min(descriptor.width, target.maxWidth);
      codec = await descriptor.instantiateCodec(targetWidth: effectiveWidth);
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec?.dispose();
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
