/// Flat equirectangular rendering of the same map and landmarks used by 3D.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/equirectangular_projection.dart';
import 'package:dayseven/features/world/ui/engines/dayseven_3d/landmark_dialog.dart';
import 'package:dayseven/features/world/world_renderer/globe_texture_loader.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DaySeven2DCanvas extends ConsumerStatefulWidget {
  const DaySeven2DCanvas({super.key});

  @override
  ConsumerState<DaySeven2DCanvas> createState() => _DaySeven2DCanvasState();
}

class _DaySeven2DCanvasState extends ConsumerState<DaySeven2DCanvas> {
  final GlobeTextureLoader _textureLoader = GlobeTextureLoader();
  String? _pendingAssetId;
  String? _pendingAssetPath;

  @override
  void initState() {
    super.initState();
    _textureLoader.addListener(_rebuild);
  }

  @override
  void dispose() {
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
    final model = open?.world.model3d ?? DaySeven3DModel();
    final visibleLayer = _firstVisibleLayer(model);
    final assetId = visibleLayer?.assetId;
    final assetPath = visibleLayer == null || session == null
        ? null
        : session.kb.assetPathFor(visibleLayer.assetId);
    _syncTexture(assetId: assetId, assetPath: assetPath);

    if (_textureLoader.texture == null) {
      return Center(
        child: DsStatusBlock(
          icon: Icons.map_outlined,
          headline: 'Add a source map',
          detail: 'Import a 2:1 equirectangular PNG or JPEG in World settings.',
          trailing: _textureLoader.isLoading
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : null,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(constraints.maxWidth, constraints.maxHeight);
        final mapSize = _fitTwoToOne(available);
        return Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              key: const Key('dayseven-2d-map-viewport'),
              minScale: 0.5,
              maxScale: 8,
              boundaryMargin: const EdgeInsets.all(200),
              constrained: false,
              child: SizedBox(
                key: const Key('dayseven-2d-map'),
                width: mapSize.width,
                height: mapSize.height,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) =>
                      _dropPin(details.localPosition, mapSize),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: RawImage(
                          image: _textureLoader.texture,
                          fit: BoxFit.fill,
                          filterQuality: FilterQuality.medium,
                        ),
                      ),
                      for (final landmark in model.landmarks)
                        _buildLandmark(landmark, mapSize),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              right: DsSpace.gap,
              bottom: DsSpace.gap,
              child: DsButton(
                key: const Key('dayseven-2d-drop-pin-button'),
                variant: ref.watch(dropPinModeProvider)
                    ? DsButtonVariant.primary
                    : DsButtonVariant.secondary,
                onPressed: () {
                  final notifier = ref.read(dropPinModeProvider.notifier);
                  notifier.state = !notifier.state;
                },
                child: Text(
                  ref.watch(dropPinModeProvider) ? 'Cancel pin' : 'Drop pin',
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLandmark(Model3DLandmark landmark, Size size) {
    final position = EquirectangularProjection.geographicToPixels(
      latitude: landmark.latitude,
      longitude: landmark.longitude,
      size: size,
    );
    return Positioned(
      key: ValueKey('2d-pin-${landmark.id}'),
      left: position.dx - 12,
      top: position.dy - 24,
      child: Tooltip(
        message: landmark.name,
        child: IconButton(
          icon: Icon(Icons.location_pin, color: context.ds.fern, size: 24),
          onPressed: () => _openOrEditLandmark(landmark),
        ),
      ),
    );
  }

  Future<void> _openOrEditLandmark(Model3DLandmark landmark) async {
    final document = landmark.document;
    if (document != null && document.isNotEmpty) {
      await ref.read(documentControllerProvider.notifier).open(document);
      if (!mounted) return;
      ref.read(viewProvider.notifier).state = DsView.editor;
      return;
    }
    await showLandmarkDialog(
      context: context,
      controller: ref.read(openWorldProvider.notifier),
      existing: landmark,
    );
  }

  Future<void> _dropPin(Offset position, Size size) async {
    if (!ref.read(dropPinModeProvider)) return;
    final coordinates = EquirectangularProjection.pixelsToGeographic(
      position: position,
      size: size,
    );
    ref.read(dropPinModeProvider.notifier).state = false;
    await showLandmarkDialog(
      context: context,
      controller: ref.read(openWorldProvider.notifier),
      initialLatitude: coordinates.latitude,
      initialLongitude: coordinates.longitude,
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
      } else {
        unawaited(_textureLoader.loadAsset(assetPath, assetId: assetId));
      }
    });
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

Size _fitTwoToOne(Size available) {
  if (available.width / available.height > 2) {
    return Size(available.height * 2, available.height);
  }
  return Size(available.width, available.width / 2);
}
