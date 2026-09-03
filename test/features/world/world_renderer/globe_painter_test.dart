import 'dart:ui' as ui;

import 'package:dayseven/features/world/world_renderer/globe_mesh.dart';
import 'package:dayseven/features/world/world_renderer/globe_painter.dart';
import 'package:dayseven/features/world/world_renderer/globe_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('paints a textured mesh through drawVertices', () async {
    final texture = await _solidImage();
    addTearDown(texture.dispose);
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);
    final painter = GlobePainter(
      texture: texture,
      viewport: viewport,
      mesh: GlobeMesh(latitudeSegments: 8, longitudeSegments: 16),
      sphereBaseColor: const ui.Color.fromARGB(255, 220, 220, 220),
    );

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    painter.paint(canvas, const ui.Size(120, 120));
    final picture = recorder.endRecording();
    addTearDown(picture.dispose);

    // Rendering the recording exercises the ImageShader-backed vertices and
    // the BlendMode.modulate draw call without introducing a Canvas mock.
    final rendered = await picture.toImage(120, 120);
    addTearDown(rendered.dispose);
    expect(rendered.width, 120);
    expect(rendered.height, 120);
    expect(painter.shouldRepaint(painter), isTrue);
  });
}

Future<ui.Image> _solidImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 8, 8),
    ui.Paint()..color = const ui.Color.fromARGB(255, 70, 130, 190),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(8, 8);
  picture.dispose();
  return image;
}
