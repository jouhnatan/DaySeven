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
    this.model3d,
  });

  /// The `kind` this object is written under.
  static const String kind = 'world';

  /// The schema this app writes.
  static const int version = 2;

  final String id;
  final String title;
  final WorldDimension dimension;
  final String? engineId;
  final List<WorldLayer> layers;

  /// Raw settings by engine id, so an engine this build does not know can
  /// still travel through a save untouched.
  final Map<String, Map<String, Object?>> engineSettings;

  /// The native DaySeven 3D model metadata, stored directly in this `.unearth` file.
  final DaySeven3DModel? model3d;

  World copyWith({
    String? id,
    String? title,
    WorldDimension? dimension,
    String? engineId,
    bool clearEngineId = false,
    List<WorldLayer>? layers,
    Map<String, Map<String, Object?>>? engineSettings,
    DaySeven3DModel? model3d,
    bool clearModel3d = false,
  }) => World(
    id: id ?? this.id,
    title: title ?? this.title,
    dimension: dimension ?? this.dimension,
    engineId: clearEngineId ? null : (engineId ?? this.engineId),
    layers: layers ?? this.layers,
    engineSettings: engineSettings ?? this.engineSettings,
    model3d: clearModel3d ? null : (model3d ?? this.model3d),
  );

  Map<String, Object?> toJson() => {
    'kind': kind,
    'version': version,
    'id': id,
    'title': title,
    'dimension': dimension.id,
    if (engineId != null && engineId!.isNotEmpty) 'engineId': engineId,
    if (layers.isNotEmpty)
      'layers': [for (final layer in layers) layer.toJson()],
    if (engineSettings.isNotEmpty)
      'engineSettings': {
        for (final entry in engineSettings.entries) entry.key: entry.value,
      },
    if (model3d case final model3d?) 'model3d': model3d.toJson(),
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

    DaySeven3DModel? model3d;
    final rawModel3d = json['model3d'];
    if (rawModel3d is Map) {
      model3d = DaySeven3DModel.fromJson(Map<String, Object?>.from(rawModel3d));
    }

    return World(
      id: _string(json['id'], fallback: 'world'),
      title: _string(json['title']),
      dimension:
          WorldDimension.parse(json['dimension']) ?? WorldDimension.threeD,
      engineId: _nonEmpty(json['engineId']),
      layers: layers,
      engineSettings: _engineSettings(json['engineSettings']),
      model3d: model3d,
    );
  }
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
