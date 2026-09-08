import 'dart:math' as math;
import 'dart:ui';

import 'package:dayseven/features/world/world_renderer/globe_mesh.dart';
import 'package:dayseven/features/world/world_renderer/globe_viewport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rotation interpolates toward its target', () {
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);

    const front = GlobeVector3(0, 0, 1);
    viewport.rotateBy(deltaPitch: math.pi / 2);
    expect(viewport.rotation.rotate(front).y, 0);

    viewport.advance(const Duration(milliseconds: 30));
    expect(viewport.rotation.rotate(front).y, lessThan(0));
    expect(viewport.rotation.rotate(front).z, greaterThan(0));

    viewport.advance(const Duration(seconds: 2));
    expect(viewport.rotation.rotate(front).y, closeTo(-1, 0.0001));
    expect(viewport.isAnimating, isFalse);
  });

  test(
    'vertical rotation remains screen-relative after horizontal rotation',
    () {
      final viewport = GlobeViewportController();
      addTearDown(viewport.dispose);

      viewport.rotateBy(deltaYaw: math.pi / 2);
      viewport.advance(const Duration(seconds: 2));
      final localFront = viewport.rotation.inverseRotate(
        const GlobeVector3(0, 0, 1),
      );

      viewport.rotateBy(deltaPitch: math.pi / 4);
      viewport.advance(const Duration(seconds: 2));
      final moved = viewport.rotation.rotate(localFront);

      expect(moved.x, closeTo(0, 0.0001));
      expect(moved.y, closeTo(-math.sqrt1_2, 0.0001));
      expect(moved.z, closeTo(math.sqrt1_2, 0.0001));
    },
  );

  test('zoom interpolates and limits its target', () {
    final viewport = GlobeViewportController();
    addTearDown(viewport.dispose);

    viewport.zoomBy(100);
    expect(viewport.scale, kGlobeMinScale);
    expect(viewport.targetScale, kGlobeMaxScale);
    viewport.advance(const Duration(milliseconds: 60));
    expect(viewport.scale, greaterThan(kGlobeMinScale));
    expect(viewport.scale, lessThan(kGlobeMaxScale));
    viewport.advance(const Duration(seconds: 2));
    expect(viewport.scale, kGlobeMaxScale);

    viewport.zoomBy(0.001);
    expect(viewport.targetScale, kGlobeMinScale);
    viewport.advance(const Duration(seconds: 2));
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
