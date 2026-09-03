/// Descriptions of engines that can produce a World.
library;

import 'package:flutter/foundation.dart';

import 'world_dimension.dart';

/// An engine descriptor, kept separate from the registry that will use it.
@immutable
class WorldEngine {
  const WorldEngine({
    required this.id,
    required this.label,
    required this.dimension,
    this.isDeprecated = false,
  });

  /// The stable id used by a World to name this engine.
  final String id;

  /// The name shown to somebody choosing an engine.
  final String label;

  /// The dimension this engine produces.
  final WorldDimension dimension;

  /// Whether this engine has been deprecated in favour of a newer engine.
  final bool isDeprecated;

  /// DaySeven 3D: native, schema-validated 3D world model with open JSON metadata.
  static const dayseven3D = WorldEngine(
    id: 'dayseven_3d',
    label: 'DaySeven 3D',
    dimension: WorldDimension.threeD,
  );

  /// World Orogen (Legacy), deprecated in favour of DaySeven 3D.
  @Deprecated('Use WorldEngine.dayseven3D instead')
  static const orogen = WorldEngine(
    id: 'orogen',
    label: 'World Orogen',
    dimension: WorldDimension.threeD,
    isDeprecated: true,
  );
}
