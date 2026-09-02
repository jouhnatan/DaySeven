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
  });

  /// The stable id used by a World to name this engine.
  final String id;

  /// The name shown to somebody choosing an engine.
  final String label;

  /// The dimension this engine produces.
  final WorldDimension dimension;

  /// World Orogen, the first engine supported by the World view.
  static const orogen = WorldEngine(
    id: 'orogen',
    label: 'World Orogen',
    dimension: WorldDimension.threeD,
  );
}
