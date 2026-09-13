/// Riverpod state for the Economy view: which tab is showing, what on the map
/// is selected, and which placement tool is armed.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/world_providers.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';

/// The three regions of the right-hand stats editor.
enum EconomyTab { locations, resources, simulate }

/// What the next click on the map does.
enum EconomyTool { none, addLocation, addNode, addRoute }

final economyTabProvider = StateProvider<EconomyTab>(
  (ref) => EconomyTab.locations,
);

/// The selected map entry: a city landmark id or a resource node id. They are
/// distinct id spaces, so one selection can name either.
final selectedEconomyLocationProvider = StateProvider<String?>((ref) => null);

/// The selected trade route.
final selectedEconomyRouteProvider = StateProvider<String?>((ref) => null);

/// The armed map tool. Placement is modal on purpose: the map cannot know
/// whether a click means "select" or "put something here" without being told.
final economyToolProvider = StateProvider<EconomyTool>(
  (ref) => EconomyTool.none,
);

/// The city the first click of a new route landed on, while the second is
/// still to come.
final economyRouteStartProvider = StateProvider<String?>((ref) => null);

/// The resource a newly placed node will collect. Defaults to the first
/// resource type the world has.
final economyNodeResourceProvider = StateProvider<String?>((ref) {
  final open = ref.watch(openWorldProvider);
  final types = open?.world.economy.resourceTypes ?? const [];
  return types.isEmpty ? null : types.first.id;
});

/// The city landmarks the Economy view owns — cities, and only cities. A
/// mountain or a ruin is a World detail, not an economic location.
final economyCitiesProvider = Provider<List<Model3DLandmark>>((ref) {
  final open = ref.watch(openWorldProvider);
  final model = open?.world.model;
  if (model == null) return const [];
  return [
    for (final landmark in model.landmarks)
      if (landmark.category == 'city') landmark,
  ];
});
