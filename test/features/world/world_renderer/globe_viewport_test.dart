import 'dart:math' as math;
import 'dart:ui';

import 'package:dayseven/features/world/world_renderer/globe_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pitch is clamped to the globe limits', () {
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);

    viewport.rotateBy(deltaPitch: math.pi);
    expect(viewport.pitch, closeTo(math.pi / 2, 0.000001));
    viewport.rotateBy(deltaPitch: -math.pi * 2);
    expect(viewport.pitch, closeTo(-math.pi / 2, 0.000001));
  });

  test('yaw wraps around the full circle', () {
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);

    viewport.rotateBy(deltaYaw: math.pi * 3);
    expect(viewport.yaw, closeTo(math.pi, 0.000001));
    viewport.rotateBy(deltaYaw: math.pi / 2);
    expect(viewport.yaw, closeTo(-math.pi / 2, 0.000001));
  });

  test('zoom limits and reset are enforced', () {
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);

    viewport.zoomBy(100);
    expect(viewport.scale, kGlobeMaxScale);
    viewport.zoomBy(0.001);
    expect(viewport.scale, kGlobeMinScale);
    viewport
      ..rotateBy(deltaPitch: 0.5, deltaYaw: 0.75)
      ..zoomIn()
      ..reset();

    expect(viewport.pitch, 0);
    expect(viewport.yaw, 0);
    expect(viewport.scale, kGlobeMinScale);
  });

  test('the viewport centre maps to zero latitude and longitude', () {
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);

    final coordinates = viewport.toSphereCoordinates(
      const Offset(100, 100),
      const Size(200, 200),
    );

    expect(coordinates, isNotNull);
    expect(coordinates!.latitude, closeTo(0, 0.000001));
    expect(coordinates.longitude, closeTo(0, 0.000001));
    expect(
      viewport.toSphereCoordinates(
        const Offset(201, 100),
        const Size(200, 200),
      ),
      isNull,
    );
  });
}
