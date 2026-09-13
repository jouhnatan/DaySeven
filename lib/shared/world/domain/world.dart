/// A World: an object of its own, stored as a `.unearth` file in the
/// Knowledge Base.
library;

import 'dayseven_3d_model.dart';
import 'world_dimension.dart';
import 'world_layer.dart';

/// Raised when a `.unearth` file cannot be read as a World.
class WorldFormatException implements Exception {
  const WorldFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One World, as stored in one `.unearth` file.
class World {
  const World({
    required this.id,
    required this.title,
    this.dimension = WorldDimension.threeD,
    this.engineId,
    this.layers = const [],
    this.engineSettings = const {},
    this.requiresMigration = false,
    DaySeven3DModel? model,
    @Deprecated('Use model') DaySeven3DModel? model3d,
  }) : model = model ?? model3d;

  /// The `kind` this object is written under.
  static const String kind = 'world';

  /// The schema this app writes.
  static const int version = 3;

  final String id;
  final String title;
  final WorldDimension dimension;
  final String? engineId;
  final List<WorldLayer> layers;

  /// Raw settings by engine id, so an engine this build does not know can
  /// still travel through a save untouched.
  final Map<String, Map<String, Object?>> engineSettings;
  final bool requiresMigration;

  /// Geographic data shared by the flat map and globe renderers.
  final DaySeven3DModel? model;

  @Deprecated('Use model')
  DaySeven3DModel? get model3d => model;

  World copyWith({
    String? id,
    String? title,
    WorldDimension? dimension,
    String? engineId,
    bool clearEngineId = false,
    List<WorldLayer>? layers,
    Map<String, Map<String, Object?>>? engineSettings,
    bool? requiresMigration,
    DaySeven3DModel? model,
    DaySeven3DModel? model3d,
    bool clearModel3d = false,
  }) => World(
    id: id ?? this.id,
    title: title ?? this.title,
    dimension: dimension ?? this.dimension,
    engineId: clearEngineId ? null : (engineId ?? this.engineId),
    layers: layers ?? this.layers,
    engineSettings: engineSettings ?? this.engineSettings,
    requiresMigration: requiresMigration ?? this.requiresMigration,
    model: clearModel3d ? null : (model ?? model3d ?? this.model),
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': version,
    'id': id,
    'title': title,
    'renderMode': dimension.id,
    if (model case final model?) 'model': model.toJson(),
  };

  static World fromJson(Map<String, Object?> json) {
    final declaredKind = _string(json['kind']);
    if (declaredKind != kind) {
      throw WorldFormatException(
        declaredKind.isEmpty
            ? 'That file does not say what kind of object it is.'
            : 'That file holds a "$declaredKind", not a world.',
      );
    }

    final declaredVersion = _int(json['version']) ?? version;
    if (declaredVersion > version) {
      throw WorldFormatException(
        'That world was written by a newer version of DaySeven '
        '(format $declaredVersion). Update before opening it, so that saving '
        'it does not discard what this version cannot read.',
      );
    }

    final layers = <WorldLayer>[];
    final rawLayers = json['layers'];
    if (rawLayers is List) {
      for (final raw in rawLayers) {
        if (raw is! Map) continue;
        final layer = WorldLayer.fromJson(Map<String, Object?>.from(raw));
        if (layer != null) layers.add(layer);
      }
    }

    DaySeven3DModel? model;
    final rawModel = json['model'] ?? json['model3d'];
    if (rawModel is Map) {
      model = DaySeven3DModel.fromJson(Map<String, Object?>.from(rawModel));
    }
    if (model != null &&
        model.sourceMapLayerId == null &&
        model.layers.isNotEmpty) {
      model = model.copyWith(
        sourceMapLayerId: _preferredSourceMapLayerId(model.layers),
      );
    }

    // v2 Orogen layers become ordinary shared map layers. Their asset files
    // are referenced in place; migration never rewrites or deletes an image.
    if (layers.isNotEmpty) {
      final current = model ?? DaySeven3DModel();
      final existingIds = {for (final layer in current.layers) layer.id};
      final migrated = <Model3DLayer>[
        ...current.layers,
        for (final layer in layers)
          if (!existingIds.contains(layer.id))
            Model3DLayer(
              id: layer.id,
              name: layer.kind.label,
              type: switch (layer.kind) {
                WorldLayerKind.heightmap ||
                WorldLayerKind.landHeightmap => Model3DLayerType.heightmap,
                WorldLayerKind.satellite => Model3DLayerType.albedo,
                WorldLayerKind.climate => Model3DLayerType.biomes,
                WorldLayerKind.landMask => Model3DLayerType.specular,
              },
              assetId: layer.assetId,
              visible: layer.visible,
            ),
      ];
      model = current.copyWith(
        layers: migrated,
        sourceMapLayerId:
            current.sourceMapLayerId ?? _preferredSourceMapLayerId(migrated),
      );
    }

    return World(
      id: _string(json['id'], fallback: 'world'),
      title: _string(json['title']),
      dimension:
          WorldDimension.parse(json['renderMode'] ?? json['dimension']) ??
          WorldDimension.threeD,
      engineId: _nonEmpty(json['engineId']),
      layers: layers,
      engineSettings: _engineSettings(json['engineSettings']),
      requiresMigration:
          declaredVersion < version ||
          json.containsKey('engineId') ||
          json.containsKey('layers') ||
          json.containsKey('engineSettings') ||
          json.containsKey('model3d'),
      model: model,
    );
  }
}

String? _preferredSourceMapLayerId(List<Model3DLayer> layers) {
  for (final layer in layers.reversed) {
    if (layer.visible && layer.type == Model3DLayerType.albedo) return layer.id;
  }
  for (final layer in layers.reversed) {
    if (layer.visible) return layer.id;
  }
  return null;
}

String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

String? _nonEmpty(Object? value) {
  final valueAsString = _string(value);
  return valueAsString.isEmpty ? null : valueAsString;
}

int? _int(Object? value) => switch (value) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

Map<String, Map<String, Object?>> _engineSettings(Object? value) {
  if (value is! Map) return <String, Map<String, Object?>>{};

  final settings = <String, Map<String, Object?>>{};
  for (final entry in value.entries) {
    if (entry.key is! String || entry.value is! Map) continue;
    final rawSettings = entry.value as Map;
    final parsed = <String, Object?>{};
    var valid = true;
    for (final setting in rawSettings.entries) {
      if (setting.key is! String) {
        valid = false;
        break;
      }
      parsed[setting.key as String] = setting.value;
    }
    if (valid) settings[entry.key as String] = parsed;
  }
  return settings;
}
