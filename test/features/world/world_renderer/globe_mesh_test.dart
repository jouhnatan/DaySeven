import 'dart:math' as math;

import 'package:dayseven/features/world/world_renderer/globe_mesh.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('vertex and triangle counts follow subdivision math', () {
    const latitudeSegments = 4;
    const longitudeSegments = 8;
    final mesh = GlobeMesh(
      latitudeSegments: latitudeSegments,
      longitudeSegments: longitudeSegments,
    );

    expect(mesh.vertexCount, (latitudeSegments + 1) * (longitudeSegments + 1));
    expect(mesh.indices.length, latitudeSegments * longitudeSegments * 6);
    expect(mesh.triangleCount, latitudeSegments * longitudeSegments * 2);
  });

  test('vertices sit at the poles and equator', () {
    const longitudeSegments = 4;
    final mesh = GlobeMesh(latitudeSegments: 2, longitudeSegments: 4);
    final rowWidth = longitudeSegments + 1;
    final southPole = mesh.vertices.first.position;
    final equatorAtZero = mesh.vertices[rowWidth + 2].position;
    final northPole = mesh.vertices[2 * rowWidth].position;

    expect(southPole.x, closeTo(0, 0.000001));
    expect(southPole.y, closeTo(-1, 0.000001));
    expect(southPole.z, closeTo(0, 0.000001));
    expect(equatorAtZero.x, closeTo(0, 0.000001));
    expect(equatorAtZero.y, closeTo(0, 0.000001));
    expect(equatorAtZero.z, closeTo(1, 0.000001));
    expect(northPole.x, closeTo(0, 0.000001));
    expect(northPole.y, closeTo(1, 0.000001));
    expect(northPole.z, closeTo(0, 0.000001));
  });

  test('the antimeridian has separate zero and one UVs', () {
    const latitudeSegments = 3;
    const longitudeSegments = 6;
    final mesh = GlobeMesh(
      latitudeSegments: latitudeSegments,
      longitudeSegments: longitudeSegments,
    );
    final rowWidth = longitudeSegments + 1;

    for (var row = 0; row <= latitudeSegments; row++) {
      expect(mesh.vertices[row * rowWidth].uv.dx, 0);
      expect(mesh.vertices[row * rowWidth + longitudeSegments].uv.dx, 1);
      expect(
        mesh.vertices[row * rowWidth].position.x,
        closeTo(
          mesh.vertices[row * rowWidth + longitudeSegments].position.x,
          0.000001,
        ),
      );
      expect(
        mesh.vertices[row * rowWidth].position.z,
        closeTo(
          mesh.vertices[row * rowWidth + longitudeSegments].position.z,
          0.000001,
        ),
      );
    }

    for (var index = 0; index < mesh.indices.length; index += 3) {
      final columns = {
        mesh.indices[index] % rowWidth,
        mesh.indices[index + 1] % rowWidth,
        mesh.indices[index + 2] % rowWidth,
      };
      expect(
        columns.contains(0) && columns.contains(longitudeSegments),
        isFalse,
      );
    }
  });

  test('back-facing triangles are removed at the horizon', () {
    final mesh = GlobeMesh(latitudeSegments: 4, longitudeSegments: 8);
    final projected = mesh.project(center: Offset.zero, radius: 100);

    expect(projected.indices.length, lessThan(mesh.indices.length));
    expect(
      projected.indices.every(
        (index) => projected.transformedVertices[index].z >= -0.000001,
      ),
      isTrue,
    );

    final rotated = mesh.project(
      center: Offset.zero,
      radius: 100,
      yaw: math.pi,
    );
    expect(rotated.indices.length, greaterThan(0));
    expect(rotated.indices.length, lessThan(mesh.indices.length));
  });
}
