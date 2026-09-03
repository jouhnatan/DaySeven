/// The engines currently available to each World dimension.
library;

import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_engine.dart';

/// Answers which engines a dimension can use.
///
/// Two-dimensional Worlds intentionally have no engine yet. That is the
/// honest current state, rather than an invitation to invent one here.
class WorldEngineRegistry {
  const WorldEngineRegistry();

  /// Returns the engines that can produce [dimension].
  List<WorldEngine> enginesFor(WorldDimension dimension) => switch (dimension) {
    WorldDimension.threeD => const [WorldEngine.orogen],
    WorldDimension.twoD => const [],
  };

  /// Finds an engine by its stable id, or null when this build does not know it.
  WorldEngine? byId(String? id) {
    if (id == null) return null;
    for (final dimension in WorldDimension.values) {
      for (final engine in enginesFor(dimension)) {
        if (engine.id == id) return engine;
      }
    }
    return null;
  }

  /// Returns the first engine for [dimension], or null when none is available.
  WorldEngine? defaultFor(WorldDimension dimension) {
    final engines = enginesFor(dimension);
    return engines.isEmpty ? null : engines.first;
  }
}
