/// Camera state and screen-to-sphere conversion for the World globe.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:flutter/foundation.dart' show ChangeNotifier;

import 'globe_mesh.dart';

const double kGlobeMinScale = 1.0;
const double kGlobeMaxScale = 8.0;

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
  GlobeRotation _rotation = GlobeRotation.identity;
  GlobeRotation _targetRotation = GlobeRotation.identity;
  double _scale = kGlobeMinScale;
  double _targetScale = kGlobeMinScale;

  GlobeRotation get rotation => _rotation;
  double get scale => _scale;
  double get targetScale => _targetScale;

  bool get isAnimating =>
      (_scale - _targetScale).abs() > 0.0001 ||
      _rotation.distanceTo(_targetRotation) > 0.0001;

  /// Adds rotation around the fixed screen axes.
  ///
  /// Composing on the left keeps an upward drag visually upward even after the
  /// globe has been turned horizontally.
  void rotateBy({double deltaPitch = 0, double deltaYaw = 0}) {
    final pitch = GlobeRotation.axisAngle(
      const GlobeVector3(1, 0, 0),
      deltaPitch,
    );
    final yaw = GlobeRotation.axisAngle(const GlobeVector3(0, 1, 0), deltaYaw);
    _targetRotation = yaw * pitch * _targetRotation;
    notifyListeners();
  }

  /// Moves the zoom target within the fixed globe limits.
  void zoomBy(double factor) {
    if (!factor.isFinite || factor <= 0) return;
    _targetScale = (_targetScale * factor)
        .clamp(kGlobeMinScale, kGlobeMaxScale)
        .toDouble();
    notifyListeners();
  }

  /// Advances the rendered camera toward its latest input targets.
  void advance(Duration elapsed) {
    if (!isAnimating) return;
    final seconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final rotationAmount = 1 - math.exp(-seconds / 0.055);
    final zoomAmount = 1 - math.exp(-seconds / 0.12);

    _rotation = GlobeRotation.slerp(_rotation, _targetRotation, rotationAmount);
    _scale += (_targetScale - _scale) * zoomAmount;

    if (_rotation.distanceTo(_targetRotation) < 0.0001) {
      _rotation = _targetRotation;
    }
    if ((_scale - _targetScale).abs() < 0.0001) {
      _scale = _targetScale;
    }
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
    final local = _rotation.inverseRotate(
      GlobeVector3(screenX, -screenY, cameraZ),
    );

    return GlobeSphereCoordinates(
      latitude: math.asin(local.y.clamp(-1.0, 1.0).toDouble()),
      longitude: math.atan2(local.x, local.z),
    );
  }
}
