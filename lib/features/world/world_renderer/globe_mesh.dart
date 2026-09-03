/// Headless UV-sphere geometry and its camera projection for the World view.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

/// A small three-dimensional vector used by the globe calculations.
class GlobeVector3 {
  const GlobeVector3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  GlobeVector3 operator +(GlobeVector3 other) =>
      GlobeVector3(x + other.x, y + other.y, z + other.z);

  GlobeVector3 operator -(GlobeVector3 other) =>
      GlobeVector3(x - other.x, y - other.y, z - other.z);

  GlobeVector3 operator *(double factor) =>
      GlobeVector3(x * factor, y * factor, z * factor);

  double dot(GlobeVector3 other) => x * other.x + y * other.y + z * other.z;

  GlobeVector3 cross(GlobeVector3 other) => GlobeVector3(
    y * other.z - z * other.y,
    z * other.x - x * other.z,
    x * other.y - y * other.x,
  );

  double get length => math.sqrt(dot(this));
}

/// One source vertex in the sphere, including its seam-safe UV coordinate.
class GlobeMeshVertex {
  const GlobeMeshVertex({
    required this.position,
    required this.uv,
    required this.normal,
  });

  final GlobeVector3 position;
  final ui.Offset uv;
  final GlobeVector3 normal;

  /// Alias for callers that use the texture terminology directly.
  ui.Offset get textureCoordinate => uv;

  /// Alias for the position's individual components in geometry code.
  double get x => position.x;
  double get y => position.y;
  double get z => position.z;
}

/// The projected, horizon-culled mesh passed to a future globe painter.
class GlobeProjectedMesh {
  const GlobeProjectedMesh({
    required this.positions,
    required this.uvs,
    required this.indices,
    required this.surfaceNormals,
    required this.transformedVertices,
  });

  /// Screen-space vertex positions.
  final List<ui.Offset> positions;

  /// Texture coordinates matching [positions].
  final List<ui.Offset> uvs;

  /// Triangle indices into [positions], with back-facing triangles removed.
  final List<int> indices;

  /// Camera-space surface normals matching [positions].
  final List<GlobeVector3> surfaceNormals;

  /// Camera-space positions retained for depth-aware lighting and inspection.
  final List<GlobeVector3> transformedVertices;

  /// The short name used by painter code for [uvs].
  List<ui.Offset> get textureCoordinates => uvs;

  /// The short name used by lighting code for [surfaceNormals].
  List<GlobeVector3> get normals => surfaceNormals;

  /// Makes the result directly consumable by [ui.Canvas.drawVertices].
  ui.Vertices toVertices() {
    final positionData = Float32List(positions.length * 2);
    final uvData = Float32List(uvs.length * 2);
    for (var index = 0; index < positions.length; index++) {
      positionData[index * 2] = positions[index].dx;
      positionData[index * 2 + 1] = positions[index].dy;
      uvData[index * 2] = uvs[index].dx;
      uvData[index * 2 + 1] = uvs[index].dy;
    }

    return ui.Vertices.raw(
      ui.VertexMode.triangles,
      positionData,
      textureCoordinates: uvData,
      indices: Uint16List.fromList(indices),
    );
  }
}

/// A UV sphere with a duplicated antimeridian seam.
class GlobeMesh {
  GlobeMesh({this.latitudeSegments = 36, this.longitudeSegments = 72})
    : assert(latitudeSegments >= 2),
      assert(longitudeSegments >= 3),
      vertices = _buildVertices(latitudeSegments, longitudeSegments),
      indices = _buildIndices(latitudeSegments, longitudeSegments);

  /// Number of subdivisions from south pole to north pole.
  final int latitudeSegments;

  /// Number of subdivisions around the full longitude circle.
  final int longitudeSegments;

  /// Vertices include both u=0 and u=1 at every latitude.
  final List<GlobeMeshVertex> vertices;

  /// Triangle indices into [vertices].
  final List<int> indices;

  int get vertexCount => vertices.length;
  int get triangleCount => indices.length ~/ 3;

  /// Rotates the sphere and projects it into a viewport-sized screen space.
  ///
  /// Longitude zero faces the camera before [yaw] is applied. Positive screen
  /// y is down, so the sphere's positive latitude projects upward.
  GlobeProjectedMesh project({
    double pitch = 0,
    double yaw = 0,
    required ui.Offset center,
    required double radius,
  }) {
    final transformed = <GlobeVector3>[];
    final positions = <ui.Offset>[];
    final uvs = <ui.Offset>[];
    final normals = <GlobeVector3>[];

    for (final vertex in vertices) {
      final rotated = _rotate(vertex.position, pitch: pitch, yaw: yaw);
      transformed.add(rotated);
      positions.add(
        ui.Offset(
          center.dx + rotated.x * radius,
          center.dy - rotated.y * radius,
        ),
      );
      uvs.add(vertex.uv);
      normals.add(_rotate(vertex.normal, pitch: pitch, yaw: yaw));
    }

    final visibleIndices = <int>[];
    for (var index = 0; index < indices.length; index += 3) {
      final a = transformed[indices[index]];
      final b = transformed[indices[index + 1]];
      final c = transformed[indices[index + 2]];
      final centroid = (a + b + c) * (1 / 3);
      final faceNormal = (b - a).cross(c - a);
      // The index winding at the poles can be degenerate. Orient a normal
      // with the sphere centre first, then keep only normals facing +Z.
      final outward = faceNormal.dot(centroid) < 0
          ? faceNormal * -1
          : faceNormal;
      if (centroid.z > 0 && outward.z > 0) {
        visibleIndices.addAll([
          indices[index],
          indices[index + 1],
          indices[index + 2],
        ]);
      }
    }

    return GlobeProjectedMesh(
      positions: positions,
      uvs: uvs,
      indices: visibleIndices,
      surfaceNormals: normals,
      transformedVertices: transformed,
    );
  }
}

List<GlobeMeshVertex> _buildVertices(
  int latitudeSegments,
  int longitudeSegments,
) {
  final vertices = <GlobeMeshVertex>[];
  for (
    var latitudeIndex = 0;
    latitudeIndex <= latitudeSegments;
    latitudeIndex++
  ) {
    final latitude = -math.pi / 2 + math.pi * latitudeIndex / latitudeSegments;
    final cosLatitude = math.cos(latitude);
    final y = math.sin(latitude);
    final v = 1 - latitudeIndex / latitudeSegments;

    for (
      var longitudeIndex = 0;
      longitudeIndex <= longitudeSegments;
      longitudeIndex++
    ) {
      final longitude =
          -math.pi + 2 * math.pi * longitudeIndex / longitudeSegments;
      final cosLongitude = math.cos(longitude);
      final sinLongitude = math.sin(longitude);
      // Keeping longitude zero at +Z makes the initial camera face the map's
      // central meridian. The first and last longitude rows remain duplicates
      // so no triangle ever interpolates from u=1 back through u=0.
      final position = GlobeVector3(
        cosLatitude * sinLongitude,
        y,
        cosLatitude * cosLongitude,
      );
      vertices.add(
        GlobeMeshVertex(
          position: position,
          uv: ui.Offset(longitudeIndex / longitudeSegments, v),
          normal: position,
        ),
      );
    }
  }
  return vertices;
}

List<int> _buildIndices(int latitudeSegments, int longitudeSegments) {
  final indices = <int>[];
  final rowWidth = longitudeSegments + 1;
  for (
    var latitudeIndex = 0;
    latitudeIndex < latitudeSegments;
    latitudeIndex++
  ) {
    for (
      var longitudeIndex = 0;
      longitudeIndex < longitudeSegments;
      longitudeIndex++
    ) {
      final topLeft = latitudeIndex * rowWidth + longitudeIndex;
      final bottomLeft = (latitudeIndex + 1) * rowWidth + longitudeIndex;
      final topRight = topLeft + 1;
      final bottomRight = bottomLeft + 1;
      indices.addAll([
        topLeft,
        bottomLeft,
        topRight,
        topRight,
        bottomLeft,
        bottomRight,
      ]);
    }
  }
  return indices;
}

GlobeVector3 _rotate(
  GlobeVector3 point, {
  required double pitch,
  required double yaw,
}) {
  final cosPitch = math.cos(pitch);
  final sinPitch = math.sin(pitch);
  final pitchedY = point.y * cosPitch - point.z * sinPitch;
  final pitchedZ = point.y * sinPitch + point.z * cosPitch;

  final cosYaw = math.cos(yaw);
  final sinYaw = math.sin(yaw);
  return GlobeVector3(
    point.x * cosYaw + pitchedZ * sinYaw,
    pitchedY,
    -point.x * sinYaw + pitchedZ * cosYaw,
  );
}
