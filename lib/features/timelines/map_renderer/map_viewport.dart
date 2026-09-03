/// Moving around a map, and zooming in and out of it.
///
/// The transform is held in a [TransformationController] rather than in a pair
/// of offset-and-scale fields, because that is what carries the whole mapping
/// between the screen and the image — including its inverse. Placing a pin is
/// the next thing this surface has to do, and a pin is a point on the *image*
/// that somebody clicked on the *screen*; [toImagePoint] is that conversion,
/// and it exists now so the transform is never reduced to something that
/// cannot express it.
library;

import 'package:flutter/material.dart';

/// How far in and out a map may be taken.
///
/// Out is capped at the fit-to-pane size rather than below it: a map smaller
/// than its pane, adrift in the middle of it, is not a view of anything.
const double kMapMinScale = 1;
const double kMapMaxScale = 8;

/// What one press of the zoom controls does.
const double kMapZoomStep = 1.6;

class MapViewportController extends ChangeNotifier {
  MapViewportController() {
    _transform.addListener(notifyListeners);
  }

  final TransformationController _transform = TransformationController();

  TransformationController get transform => _transform;

  /// The current magnification. 1 is the whole map, fitted to the pane.
  double get scale => _transform.value.getMaxScaleOnAxis();

  bool get canZoomIn => scale < kMapMaxScale - 0.001;
  bool get canZoomOut => scale > kMapMinScale + 0.001;

  /// Where [screenPoint] falls on the map, in the coordinates of the widget
  /// being transformed — so a point that stays put on the image as the map is
  /// panned and zoomed.
  ///
  /// Not called yet: pin placement is what it is for.
  Offset toImagePoint(Offset screenPoint) {
    final inverted = Matrix4.inverted(_transform.value);
    return MatrixUtils.transformPoint(inverted, screenPoint);
  }

  /// Zooms about the centre of a pane of [size].
  void zoomBy(double factor, Size size) {
    final next = (scale * factor).clamp(kMapMinScale, kMapMaxScale);
    if (next == scale) return;
    _scaleAbout(next / scale, Offset(size.width / 2, size.height / 2));
  }

  void zoomIn(Size size) => zoomBy(kMapZoomStep, size);

  void zoomOut(Size size) => zoomBy(1 / kMapZoomStep, size);

  /// Back to the whole map.
  void reset() => _transform.value = Matrix4.identity();

  void _scaleAbout(double factor, Offset focus) {
    _transform.value = _transform.value.clone()
      ..translateByDouble(focus.dx, focus.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-focus.dx, -focus.dy, 0, 1);
  }

  @override
  void dispose() {
    _transform
      ..removeListener(notifyListeners)
      ..dispose();
    super.dispose();
  }
}
