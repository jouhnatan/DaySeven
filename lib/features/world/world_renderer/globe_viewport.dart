/// Camera state and screen-to-sphere conversion for the World globe.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show ChangeNotifier;

const double kGlobeMinScale = 1.0;
const double kGlobeMaxScale = 8.0;
const double kGlobeZoomStep = 1.6;

/// A latitude and longitude found on the visible globe hemisphere.
class GlobeSphereCoordinates {
  const GlobeSphereCoordinates({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;

  /// Short aliases for callers using the conventional names.
  double get lat => latitude;
  double get lon => longitude;
}

/// Interactive camera state for the headless globe renderer.
class GlobeViewportController extends ChangeNotifier {
  double _pitch = 0;
  double _yaw = 0;
  double _scale = kGlobeMinScale;

  double get pitch => _pitch;
  double get yaw => _yaw;
  double get scale => _scale;

  bool get canZoomIn => _scale < kGlobeMaxScale;
  bool get canZoomOut => _scale > kGlobeMinScale;

  /// Rotates the camera, keeping latitude within the visible globe range.
  void rotateBy({double deltaPitch = 0, double deltaYaw = 0}) {
    _pitch = (_pitch + deltaPitch).clamp(-math.pi / 2, math.pi / 2).toDouble();
    _yaw = _wrapYaw(_yaw + deltaYaw);
    notifyListeners();
  }

  /// Changes magnification within the fixed globe limits.
  void zoomBy(double factor) {
    _scale = (_scale * factor).clamp(kGlobeMinScale, kGlobeMaxScale).toDouble();
    notifyListeners();
  }

  void zoomIn() => zoomBy(kGlobeZoomStep);

  void zoomOut() => zoomBy(1 / kGlobeZoomStep);

  /// Returns the camera to the centre of the whole globe.
  void reset() {
    _pitch = 0;
    _yaw = 0;
    _scale = kGlobeMinScale;
    notifyListeners();
  }

  /// Converts a screen point to latitude/longitude, or null outside the disc.
  ///
  /// The globe is fitted to the shorter viewport edge at scale one. A point
  /// on the disc's rim is on the horizon; its camera-space z is zero.
  GlobeSphereCoordinates? toSphereCoordinates(
    Offset screenPoint,
    Size viewportSize,
  ) {
    final radius =
        math.min(viewportSize.width, viewportSize.height) / 2 * _scale;
    if (!(radius > 0)) return null;

    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final screenX = (screenPoint.dx - center.dx) / radius;
    final screenY = (screenPoint.dy - center.dy) / radius;
    final distanceSquared = screenX * screenX + screenY * screenY;
    if (distanceSquared > 1) return null;

    final cameraZ = math.sqrt(math.max(0, 1 - distanceSquared));
    // Undo the same Y-then-X camera rotations used by GlobeMesh.project.
    final cosYaw = math.cos(_yaw);
    final sinYaw = math.sin(_yaw);
    final yawAdjustedX = screenX * cosYaw - cameraZ * sinYaw;
    final yawAdjustedZ = screenX * sinYaw + cameraZ * cosYaw;
    final cameraY = -screenY;
    final cosPitch = math.cos(_pitch);
    final sinPitch = math.sin(_pitch);
    final localY = cameraY * cosPitch + yawAdjustedZ * sinPitch;
    final localX = yawAdjustedX;
    final localZ = -cameraY * sinPitch + yawAdjustedZ * cosPitch;

    return GlobeSphereCoordinates(
      latitude: math.asin(localY.clamp(-1.0, 1.0).toDouble()),
      longitude: math.atan2(localX, localZ),
    );
  }
}

double _wrapYaw(double value) {
  final fullTurn = 2 * math.pi;
  var wrapped = (value + math.pi) % fullTurn;
  if (wrapped < 0) wrapped += fullTurn;
  wrapped -= math.pi;
  // Keep the positive boundary representable while retaining [-pi, pi].
  if (wrapped == -math.pi && value > 0) return math.pi;
  return wrapped;
}
