import 'dart:ui';

import 'package:dayseven/features/world/domain/equirectangular_projection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps geographic reference points to equirectangular UVs', () {
    expect(
      EquirectangularProjection.geographicToUv(latitude: 0, longitude: 0),
      const Offset(0.5, 0.5),
    );
    expect(
      EquirectangularProjection.geographicToUv(latitude: 90, longitude: -180),
      const Offset(0, 0),
    );
    expect(
      EquirectangularProjection.geographicToUv(latitude: -90, longitude: 180),
      const Offset(1, 1),
    );
  });

  test('round trips geographic coordinates through map pixels', () {
    const size = Size(4096, 2048);
    final pixels = EquirectangularProjection.geographicToPixels(
      latitude: 52.4,
      longitude: -3.1,
      size: size,
    );
    final result = EquirectangularProjection.pixelsToGeographic(
      position: pixels,
      size: size,
    );
    expect(result.latitude, closeTo(52.4, 1e-10));
    expect(result.longitude, closeTo(-3.1, 1e-10));
  });

  test('uses the globe Y-north and central-meridian orientation', () {
    expect(
      EquirectangularProjection.sphereToUv(x: 0, y: 0, z: 1),
      const Offset(0.5, 0.5),
    );
    expect(
      EquirectangularProjection.sphereToUv(x: 0, y: 1, z: 0),
      const Offset(0.5, 0),
    );
  });
}
