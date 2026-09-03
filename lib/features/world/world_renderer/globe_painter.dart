/// Paints the World globe's projected mesh and its bounded texture.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'globe_mesh.dart';
import 'globe_viewport.dart';

/// Renders one camera view of a World globe.
class GlobePainter extends CustomPainter {
  const GlobePainter({
    required this.texture,
    required this.viewport,
    required this.mesh,
    required this.sphereBaseColor,
    this.lightingAngle = 45.0,
  });

  final ui.Image? texture;
  final GlobeViewportController viewport;
  final GlobeMesh mesh;

  /// The sun's azimuth in degrees, measured from the globe's front meridian.
  final double lightingAngle;

  /// The colour used when there is no image texture to shade.
  final Color sphereBaseColor;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 * viewport.scale;
    final center = Offset(size.width / 2, size.height / 2);
    final projected = mesh.project(
      pitch: viewport.pitch,
      yaw: viewport.yaw,
      center: center,
      radius: radius,
    );
    if (projected.indices.isEmpty) return;

    final positions = Float32List(projected.positions.length * 2);
    for (var index = 0; index < projected.positions.length; index++) {
      final position = projected.positions[index];
      positions[index * 2] = position.dx;
      positions[index * 2 + 1] = position.dy;
    }

    Float32List? textureCoordinates;
    if (texture != null) {
      textureCoordinates = Float32List(projected.uvs.length * 2);
      for (var index = 0; index < projected.uvs.length; index++) {
        final uv = projected.uvs[index];
        textureCoordinates[index * 2] = uv.dx * texture!.width;
        textureCoordinates[index * 2 + 1] = uv.dy * texture!.height;
      }
    }

    final lightAngle = lightingAngle * math.pi / 180;
    final lightDirection = GlobeVector3(
      math.sin(lightAngle),
      0,
      math.cos(lightAngle),
    );
    final colors = Int32List(projected.surfaceNormals.length);
    for (var index = 0; index < projected.surfaceNormals.length; index++) {
      final diffuse = projected.surfaceNormals[index]
          .dot(lightDirection)
          .clamp(0.15, 1.0)
          .toDouble();
      final channel = (255 * diffuse).toInt();
      colors[index] = Color.fromARGB(255, channel, channel, channel).toARGB32();
    }

    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      positions,
      textureCoordinates: textureCoordinates,
      colors: colors,
      indices: Uint16List.fromList(projected.indices),
    );
    final paint = Paint();
    if (texture != null) {
      paint.shader = ui.ImageShader(
        texture!,
        ui.TileMode.clamp,
        ui.TileMode.clamp,
        Float64List.fromList(Matrix4.identity().storage),
      );
    } else {
      paint.color = sphereBaseColor;
    }
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
  }

  /// The viewport is a mutable listenable, so the canvas is always repainted
  /// when its owner rebuilds after a camera change.
  @override
  bool shouldRepaint(covariant GlobePainter oldDelegate) => true;
}
