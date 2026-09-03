/// The interactive Orogen globe surface in the World centre slot.
library;

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

import '../../globe_mesh.dart';
import '../../globe_painter.dart';
import '../../globe_texture_loader.dart';
import '../../globe_viewport.dart';

/// The Orogen canvas owns the camera and the one decoded texture it displays.
class OrogenCanvas extends ConsumerStatefulWidget {
  const OrogenCanvas({super.key});

  @override
  ConsumerState<OrogenCanvas> createState() => _OrogenCanvasState();
}

class _OrogenCanvasState extends ConsumerState<OrogenCanvas> {
  final GlobeViewportController _viewport = GlobeViewportController();
  final GlobeTextureLoader _textureLoader = GlobeTextureLoader();
  final GlobeMesh _mesh = GlobeMesh();
  String? _pendingAssetId;
  String? _pendingAssetPath;
  double _lastGestureScale = 1;

  @override
  void initState() {
    super.initState();
    _viewport.addListener(_rebuild);
    _textureLoader.addListener(_rebuild);
  }

  @override
  void dispose() {
    _viewport
      ..removeListener(_rebuild)
      ..dispose();
    _textureLoader
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openWorldProvider);
    final session = ref.watch(kbSessionProvider);
    final visibleLayer = _firstVisibleLayer(open);
    final assetId = visibleLayer?.assetId;
    final assetPath = visibleLayer == null || session == null
        ? null
        : session.kb.assetPathFor(visibleLayer.assetId);
    _syncTexture(assetId: assetId, assetPath: assetPath);

    return LayoutBuilder(
      builder: (context, constraints) {
        final colors = context.ds;
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerSignal: _onPointerSignal,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onScaleStart: (_) => _lastGestureScale = 1,
                  onScaleUpdate: (details) {
                    const sensitivity = 0.005;
                    _viewport.rotateBy(
                      deltaYaw: details.focalPointDelta.dx * sensitivity,
                      deltaPitch: -details.focalPointDelta.dy * sensitivity,
                    );
                    final scaleChanged =
                        details.scale > 0 && details.scale != _lastGestureScale;
                    if (details.pointerCount > 1 || scaleChanged) {
                      if (scaleChanged) {
                        _viewport.zoomBy(details.scale / _lastGestureScale);
                      }
                    }
                    _lastGestureScale = details.scale;
                  },
                  onScaleEnd: (_) => _lastGestureScale = 1,
                  child: CustomPaint(
                    key: const Key('orogen-globe'),
                    painter: GlobePainter(
                      texture: _textureLoader.texture,
                      viewport: _viewport,
                      mesh: _mesh,
                      sphereBaseColor: colors.cardSurface,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
            if (visibleLayer == null)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(DsSpace.l),
                  child: Text(
                    'No world layers yet. Import an equirectangular PNG in '
                    'World settings.',
                    textAlign: TextAlign.center,
                    style: uiTextStyle(size: 13, color: colors.faint),
                  ),
                ),
              ),
            Positioned(
              right: DsSpace.gap,
              bottom: DsSpace.gap,
              child: _OrogenControls(viewport: _viewport),
            ),
          ],
        );
      },
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
      // The ambient globe remains useful when a bundle asset is unavailable.
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (event.scrollDelta.dy < 0) {
      _viewport.zoomIn();
    } else if (event.scrollDelta.dy > 0) {
      _viewport.zoomOut();
    }
  }
}

WorldLayer? _firstVisibleLayer(OpenWorld? open) {
  for (final layer in open?.world.layers ?? const <WorldLayer>[]) {
    if (layer.visible) return layer;
  }
  return null;
}

class _OrogenControls extends StatelessWidget {
  const _OrogenControls({required this.viewport});

  final GlobeViewportController viewport;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return AnimatedBuilder(
      animation: viewport,
      builder: (context, _) {
        Widget button({
          required Key key,
          required IconData icon,
          required String tooltip,
          required VoidCallback? onPressed,
        }) => Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: DsSize.smallControl,
            child: DsButton(
              key: key,
              height: DsSize.smallControl,
              padding: EdgeInsets.zero,
              semanticLabel: tooltip,
              onPressed: onPressed,
              child: Icon(
                icon,
                size: 16,
                color: onPressed == null ? colors.faint : colors.text,
              ),
            ),
          ),
        );

        return Container(
          padding: const EdgeInsets.all(DsSpace.xs),
          decoration: BoxDecoration(
            color: colors.island,
            borderRadius: const BorderRadius.all(DsRadius.menu),
            border: Border.all(color: colors.surfaceOutline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              button(
                key: const Key('world-zoom-out'),
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: viewport.canZoomOut ? viewport.zoomOut : null,
              ),
              const SizedBox(width: DsSpace.xxs),
              button(
                key: const Key('world-zoom-in'),
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: viewport.canZoomIn ? viewport.zoomIn : null,
              ),
              const SizedBox(width: DsSpace.xxs),
              button(
                key: const Key('world-reset'),
                icon: Icons.fit_screen_outlined,
                tooltip: 'Reset the globe',
                onPressed:
                    viewport.canZoomOut ||
                        viewport.pitch != 0 ||
                        viewport.yaw != 0
                    ? viewport.reset
                    : null,
              ),
            ],
          ),
        );
      },
    );
  }
}
