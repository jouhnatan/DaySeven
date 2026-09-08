/// The interactive DaySeven 3D globe surface in the World centre slot.
///
/// Renders planetary geometry with multi-texture layers, environmental shading
/// (atmosphere, ocean, sun lighting), and landmark pins projected onto the
/// spherical mesh with direct links to Knowledge Base documents.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/scheduler.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/ui/engines/dayseven_3d/landmark_dialog.dart';
import 'package:dayseven/features/world/world_renderer/globe_mesh.dart';
import 'package:dayseven/features/world/world_renderer/globe_painter.dart';
import 'package:dayseven/features/world/world_renderer/globe_texture_loader.dart';
import 'package:dayseven/features/world/world_renderer/globe_viewport.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DaySeven3DCanvas extends ConsumerStatefulWidget {
  const DaySeven3DCanvas({super.key});

  @override
  ConsumerState<DaySeven3DCanvas> createState() => _DaySeven3DCanvasState();
}

class _DaySeven3DCanvasState extends ConsumerState<DaySeven3DCanvas>
    with SingleTickerProviderStateMixin {
  final GlobeViewportController _viewport = GlobeViewportController();
  final GlobeTextureLoader _textureLoader = GlobeTextureLoader();
  final GlobeMesh _mesh = GlobeMesh();
  late final Ticker _cameraTicker;
  String? _pendingAssetId;
  String? _pendingAssetPath;
  double _lastGestureScale = 1;
  Duration? _lastCameraTick;

  @override
  void initState() {
    super.initState();
    _cameraTicker = createTicker(_onCameraTick);
    _viewport.addListener(_onViewportChanged);
    _textureLoader.addListener(_rebuild);
  }

  @override
  void dispose() {
    _cameraTicker.dispose();
    _viewport
      ..removeListener(_onViewportChanged)
      ..dispose();
    _textureLoader
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onViewportChanged() {
    if (_viewport.isAnimating && !_cameraTicker.isActive) {
      _lastCameraTick = null;
      _cameraTicker.start();
    }
    _rebuild();
  }

  void _onCameraTick(Duration elapsed) {
    final previous = _lastCameraTick;
    _lastCameraTick = elapsed;
    if (previous == null) return;
    _viewport.advance(elapsed - previous);
    if (!_viewport.isAnimating) {
      _cameraTicker.stop();
      _lastCameraTick = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openWorldProvider);
    final session = ref.watch(kbSessionProvider);
    final model = open?.world.model3d ?? DaySeven3DModel();

    final visibleLayer = _firstVisibleLayer(model);
    final assetId = visibleLayer?.assetId;
    final assetPath = visibleLayer == null || session == null
        ? null
        : session.kb.assetPathFor(visibleLayer.assetId);
    _syncTexture(assetId: assetId, assetPath: assetPath);

    return LayoutBuilder(
      builder: (context, constraints) {
        final colors = context.ds;
        final radius =
            math.min(constraints.maxWidth, constraints.maxHeight) /
            2 *
            _viewport.scale;
        final center = Offset(
          constraints.maxWidth / 2,
          constraints.maxHeight / 2,
        );

        final projectedLandmarks = _projectLandmarks(
          model.landmarks,
          center: center,
          radius: radius,
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            // Interactive 3D Globe gesture detector and canvas
            Positioned.fill(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onSecondaryTapUp: (details) => _attemptDropPinAt(
                    details.localPosition,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                  onLongPressStart: (details) => _attemptDropPinAt(
                    details.localPosition,
                    Size(constraints.maxWidth, constraints.maxHeight),
                  ),
                  onScaleStart: (_) => _lastGestureScale = 1,
                  onScaleUpdate: (details) {
                    const sensitivity = 0.005;
                    _viewport.rotateBy(
                      deltaYaw: details.focalPointDelta.dx * sensitivity,
                      deltaPitch: -details.focalPointDelta.dy * sensitivity,
                    );
                    final scaleChanged =
                        details.scale > 0 && details.scale != _lastGestureScale;
                    if (scaleChanged) {
                      _viewport.zoomBy(details.scale / _lastGestureScale);
                    }
                    _lastGestureScale = details.scale;
                  },
                  onScaleEnd: (_) => _lastGestureScale = 1,
                  child: CustomPaint(
                    key: const Key('dayseven-3d-globe'),
                    painter: _DaySeven3DGlobePainter(
                      texture: _textureLoader.texture,
                      viewport: _viewport,
                      mesh: _mesh,
                      model: model,
                      sphereBaseColor: colors.cardSurface,
                      atmosphereGlowColor: colors.fern,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),

            // Landmark billboard pins projected onto globe front-facing hemisphere
            for (final item in projectedLandmarks)
              Positioned(
                key: ValueKey('pin-${item.landmark.id}'),
                left: item.screenPosition.dx - 12,
                top: item.screenPosition.dy - 24,
                child: _LandmarkPinWidget(
                  landmark: item.landmark,
                  depth: item.depth,
                  onTap: () {
                    if (item.landmark.document != null &&
                        item.landmark.document!.isNotEmpty) {
                      _handleLandmarkTap(item.landmark);
                    } else {
                      _handleLandmarkEdit(item.landmark);
                    }
                  },
                  onEdit: () => _handleLandmarkEdit(item.landmark),
                ),
              ),

            // Empty state notice when no textures are attached
            if (visibleLayer == null)
              Positioned(
                top: DsSpace.m,
                left: DsSpace.m,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DsSpace.m,
                    vertical: DsSpace.s,
                  ),
                  decoration: BoxDecoration(
                    color: colors.island.withValues(alpha: 0.85),
                    borderRadius: const BorderRadius.all(DsRadius.menu),
                    border: Border.all(color: colors.border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline, size: 14, color: colors.muted),
                      const SizedBox(width: DsSpace.xs),
                      Text(
                        'Base mesh • Import a PNG or JPEG source map in World Settings',
                        style: uiTextStyle(size: 12, color: colors.muted),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _attemptDropPinAt(Offset localPosition, Size size) {
    final coords = _viewport.toSphereCoordinates(localPosition, size);
    if (coords == null) return;

    final latDeg = (coords.latitude * 180.0 / math.pi).clamp(-90.0, 90.0);
    final lonDeg = (coords.longitude * 180.0 / math.pi).clamp(-180.0, 180.0);

    showLandmarkDialog(
      context: context,
      controller: ref.read(openWorldProvider.notifier),
      initialLatitude: latDeg,
      initialLongitude: lonDeg,
    );
  }

  Future<void> _handleLandmarkEdit(Model3DLandmark landmark) async {
    await showLandmarkDialog(
      context: context,
      controller: ref.read(openWorldProvider.notifier),
      existing: landmark,
    );
  }

  void _syncTexture({required String? assetId, required String? assetPath}) {
    if (_pendingAssetId == assetId && _pendingAssetPath == assetPath) return;
    _pendingAssetId = assetId;
    _pendingAssetPath = assetPath;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          _pendingAssetId != assetId ||
          _pendingAssetPath != assetPath) {
        return;
      }
      if (assetId == null || assetPath == null) {
        _textureLoader.clear();
        return;
      }
      if (assetId == _textureLoader.currentAssetId &&
          _textureLoader.texture != null) {
        return;
      }
      unawaited(_loadTexture(assetPath, assetId));
    });
  }

  Future<void> _loadTexture(String assetPath, String assetId) async {
    try {
      await _textureLoader.loadAsset(assetPath, assetId: assetId);
    } on Object {
      // The ambient globe remains useful when an asset is unavailable.
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    const sensitivity = 0.003;
    _viewport.zoomBy(math.exp(-event.scrollDelta.dy * sensitivity));
  }

  Future<void> _handleLandmarkTap(Model3DLandmark landmark) async {
    final doc = landmark.document;
    if (doc != null && doc.isNotEmpty) {
      await ref.read(documentControllerProvider.notifier).open(doc);
      if (!mounted) return;
      ref.read(viewProvider.notifier).state = DsView.editor;
    }
  }

  List<_ProjectedLandmark> _projectLandmarks(
    List<Model3DLandmark> landmarks, {
    required Offset center,
    required double radius,
  }) {
    final results = <_ProjectedLandmark>[];
    for (final landmark in landmarks) {
      final latRad = landmark.latitude * math.pi / 180.0;
      final lonRad = landmark.longitude * math.pi / 180.0;
      final cosLat = math.cos(latRad);

      final spherical = GlobeVector3(
        cosLat * math.sin(lonRad),
        math.sin(latRad),
        cosLat * math.cos(lonRad),
      );

      final rotated = _viewport.rotation.rotate(spherical);

      // Only project landmarks on the front-facing hemisphere
      if (rotated.z > 0.05) {
        final screenPos = Offset(
          center.dx + rotated.x * radius,
          center.dy - rotated.y * radius,
        );
        results.add(
          _ProjectedLandmark(
            landmark: landmark,
            screenPosition: screenPos,
            depth: rotated.z,
          ),
        );
      }
    }
    return results;
  }
}

class _ProjectedLandmark {
  const _ProjectedLandmark({
    required this.landmark,
    required this.screenPosition,
    required this.depth,
  });

  final Model3DLandmark landmark;
  final Offset screenPosition;
  final double depth;
}

class _LandmarkPinWidget extends StatelessWidget {
  const _LandmarkPinWidget({
    required this.landmark,
    required this.depth,
    required this.onTap,
    this.onEdit,
  });

  final Model3DLandmark landmark;
  final double depth;
  final VoidCallback onTap;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final hasDoc = landmark.document != null && landmark.document!.isNotEmpty;
    final opacity = (depth * 2.0).clamp(0.4, 1.0);

    final tooltip =
        '${landmark.name} (${landmark.latitude.toStringAsFixed(1)}°, ${landmark.longitude.toStringAsFixed(1)}°)'
        '${hasDoc ? "\nLinked to ${landmark.document} (Click to open)" : "\n(Click to edit)"}';

    return Opacity(
      opacity: opacity,
      child: Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: hasDoc
              ? '${landmark.name}, open document ${landmark.document}'
              : '${landmark.name}, edit landmark',
          child: GestureDetector(
            onTap: onTap,
            onSecondaryTap: onEdit,
            behavior: HitTestBehavior.opaque,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DsSpace.xs,
                    vertical: DsSpace.xxs,
                  ),
                  decoration: BoxDecoration(
                    color: colors.island.withValues(alpha: 0.9),
                    borderRadius: const BorderRadius.all(DsRadius.control),
                    border: Border.all(color: colors.border),
                  ),
                  child: Text(
                    landmark.name,
                    style: uiTextStyle(
                      size: 10,
                      weight: 600,
                      color: hasDoc ? colors.fern : colors.text,
                    ),
                  ),
                ),
                Icon(
                  _iconForCategory(landmark.category),
                  size: 20,
                  color: hasDoc ? colors.fern : colors.text,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

IconData _iconForCategory(String category) {
  switch (category.toLowerCase()) {
    case 'mountain':
      return Icons.terrain;
    case 'ruin':
      return Icons.fort;
    case 'port':
      return Icons.anchor;
    case 'city':
      return Icons.location_city;
    case 'landmark':
    default:
      return Icons.location_on;
  }
}

class _DaySeven3DGlobePainter extends CustomPainter {
  _DaySeven3DGlobePainter({
    required this.texture,
    required this.viewport,
    required this.mesh,
    required this.model,
    required this.sphereBaseColor,
    required this.atmosphereGlowColor,
  }) : _innerPainter = GlobePainter(
         texture: texture,
         viewport: viewport,
         mesh: mesh,
         sphereBaseColor: sphereBaseColor,
         lightingAngle: model.environment.lighting.sunAzimuthDeg,
       ),
       super(repaint: viewport);

  final dynamic texture;
  final GlobeViewportController viewport;
  final GlobeMesh mesh;
  final DaySeven3DModel model;
  final Color sphereBaseColor;
  final Color atmosphereGlowColor;
  final GlobePainter _innerPainter;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) / 2 * viewport.scale;
    final center = Offset(size.width / 2, size.height / 2);

    // Draw the 3D globe mesh
    _innerPainter.paint(canvas, size);

    // Render atmospheric glow rim if enabled
    if (model.environment.atmosphere.enabled) {
      final atmosphere = model.environment.atmosphere;
      final rimWidth = math.max(2.0, radius * 0.04 * atmosphere.density);
      final atmospherePaint = Paint()
        ..color = atmosphereGlowColor.withValues(
          alpha: 0.35 * atmosphere.density.clamp(0.0, 1.0),
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = rimWidth
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.0);

      canvas.drawCircle(center, radius + (rimWidth / 3), atmospherePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DaySeven3DGlobePainter oldDelegate) {
    return oldDelegate.texture != texture ||
        oldDelegate.model != model ||
        oldDelegate.sphereBaseColor != sphereBaseColor ||
        oldDelegate.atmosphereGlowColor != atmosphereGlowColor;
  }
}

Model3DLayer? _firstVisibleLayer(DaySeven3DModel model) {
  final sourceId = model.sourceMapLayerId;
  if (sourceId != null) {
    for (final layer in model.layers) {
      if (layer.id == sourceId && layer.visible) return layer;
    }
  }
  for (final layer in model.layers) {
    if (layer.visible) return layer;
  }
  return null;
}
