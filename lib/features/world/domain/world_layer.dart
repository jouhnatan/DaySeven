/// The image layers a World renderer can place over its surface.
library;

import 'package:flutter/foundation.dart';

import 'world_metadata.dart';

/// The five image exports produced by World Orogen.
enum WorldLayerKind {
  satellite('satellite', 'Satellite'),
  climate('climate', 'Climate'),
  heightmap('heightmap', 'Heightmap'),
  landHeightmap('land_heightmap', 'Land Heightmap'),
  landMask('land_mask', 'Land Mask');

  const WorldLayerKind(this.id, this.label);

  /// The stable id written to a `.unearth` file.
  final String id;

  /// The label shown in the layer controls.
  final String label;

  static WorldLayerKind? parse(Object? value) {
    if (value is! String) return null;
    final id = value.trim().toLowerCase();
    for (final kind in values) {
      if (kind.id == id) return kind;
    }
    return null;
  }
}

/// One imported image and the information learned from it.
@immutable
class WorldLayer {
  const WorldLayer({
    required this.id,
    required this.kind,
    required this.assetId,
    this.metadata,
    this.visible = true,
  });

  final String id;
  final WorldLayerKind kind;
  final String assetId;
  final WorldMetadata? metadata;
  final bool visible;

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.id,
    'assetId': assetId,
    if (metadata != null) 'metadata': metadata!.toJson(),
    if (!visible) 'visible': false,
  };

  static WorldLayer? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final kind = WorldLayerKind.parse(json['kind']);
    final assetId = _string(json['assetId']);
    if (id.isEmpty || kind == null || assetId.isEmpty) return null;

    final rawMetadata = json['metadata'];
    return WorldLayer(
      id: id,
      kind: kind,
      assetId: assetId,
      metadata: rawMetadata is Map
          ? WorldMetadata.fromJson(Map<String, Object?>.from(rawMetadata))
          : null,
      visible: json['visible'] != false,
    );
  }
}

String _string(Object? value) => value is String ? value : '';
