/// The single geographic projection shared by the flat map and globe texture.
library;

import 'dart:math' as math;
import 'dart:ui';

/// Converts between geographic degrees, normalized texture UVs, and map pixels.
///
/// Longitude -180° is the left edge, longitude +180° is the right edge,
/// latitude +90° is the top edge, and latitude -90° is the bottom edge.
abstract final class EquirectangularProjection {
  static Offset geographicToUv({
    required double latitude,
    required double longitude,
  }) {
    final clampedLatitude = latitude.clamp(-90.0, 90.0);
    final wrappedLongitude = _wrapLongitude(longitude);
    return Offset(
      (wrappedLongitude + 180.0) / 360.0,
      (90.0 - clampedLatitude) / 180.0,
    );
  }

  static ({double latitude, double longitude}) uvToGeographic(Offset uv) {
    final u = uv.dx.clamp(0.0, 1.0);
    final v = uv.dy.clamp(0.0, 1.0);
    return (latitude: 90.0 - v * 180.0, longitude: u * 360.0 - 180.0);
  }

  static Offset geographicToPixels({
    required double latitude,
    required double longitude,
    required Size size,
  }) {
    final uv = geographicToUv(latitude: latitude, longitude: longitude);
    return Offset(uv.dx * size.width, uv.dy * size.height);
  }

  static ({double latitude, double longitude}) pixelsToGeographic({
    required Offset position,
    required Size size,
  }) {
    if (size.width <= 0 || size.height <= 0) {
      return (latitude: 0.0, longitude: 0.0);
    }
    return uvToGeographic(
      Offset(position.dx / size.width, position.dy / size.height),
    );
  }

  static double _wrapLongitude(double longitude) {
    if (!longitude.isFinite) return 0.0;
    if (longitude == 180.0) return 180.0;
    return ((longitude + 180.0) % 360.0 + 360.0) % 360.0 - 180.0;
  }

  /// Converts a unit sphere position, with positive Y pointing north, to UV.
  static Offset sphereToUv({
    required double x,
    required double y,
    required double z,
  }) {
    final radius = math.sqrt(x * x + y * y + z * z);
    if (radius == 0 || !radius.isFinite) return const Offset(0.5, 0.5);
    final longitude = math.atan2(x, z) * 180.0 / math.pi;
    final latitude = math.asin((y / radius).clamp(-1.0, 1.0)) * 180.0 / math.pi;
    return geographicToUv(latitude: latitude, longitude: longitude);
  }
}
