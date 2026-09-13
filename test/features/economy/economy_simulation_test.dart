/// The trade run is rebuilt from the saved World whenever an input it was
/// built from changes, and kept when nothing did.
library;

import 'package:dayseven/features/economy/application/economy_simulation.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/economy.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:flutter_test/flutter_test.dart';

/// Two cities, one producing location and one route between them: enough that
/// population decides the number of workers and traders a rebuild produces.
World world({
  String id = 'world-1',
  int population = 400,
  Map<String, int> personCounts = const {},
}) => World(
  id: id,
  title: 'Aster',
  model: DaySeven3DModel(
    landmarks: [
      Model3DLandmark(
        id: 'aldenmoor',
        name: 'Aldenmoor',
        latitude: 1,
        longitude: 2,
      ),
      Model3DLandmark(
        id: 'oakhaven',
        name: 'Oakhaven',
        latitude: 10,
        longitude: 20,
      ),
    ],
  ),
  economy: WorldEconomy(
    resourceTypes: const [
      ResourceType(id: 'stone', name: 'Stone', color: 'slate'),
    ],
    locations: [
      EconomyLocation(
        id: 'e1',
        landmarkId: 'aldenmoor',
        population: population,
        personCounts: personCounts,
        resourceIds: const ['stone'],
      ),
    ],
    tradeRoutes: [
      TradeRoute(
        id: 'r1',
        fromLandmarkId: 'aldenmoor',
        toLandmarkId: 'oakhaven',
      ),
    ],
    resourceNodes: [
      ResourceNode(
        id: 'n1',
        resourceId: 'stone',
        latitude: 3,
        longitude: 4,
        homeLandmarkId: 'aldenmoor',
      ),
    ],
  ),
);

void main() {
  test('a population change rebuilds the run it decides the size of', () {
    final controller = EconomySimulationController()
      ..configure(world(population: 400));
    final before = controller.simulation!;

    controller.configure(world(population: 4000));

    expect(controller.simulation, isNot(same(before)));
    // One worker grows to the cap of five, and the city trades with more
    // traders, so the rebuild is visible in the agents it runs.
    expect(
      controller.simulation!.agents.length,
      greaterThan(before.agents.length),
    );
  });

  test('switching to a World with the same network rebuilds the run', () {
    final controller = EconomySimulationController()..configure(world());
    final before = controller.simulation!;

    controller.configure(world(id: 'world-2'));

    expect(controller.simulation, isNot(same(before)));
  });

  test('an unchanged World keeps the run, and its stockpiles', () {
    final controller = EconomySimulationController()..configure(world());
    final before = controller.simulation!;
    before.advance(5);

    // A fresh World object holding the same data: an unrelated save (a
    // landmark moved, the title edited) must not throw the run away.
    controller.configure(world());

    expect(controller.simulation, same(before));
    expect(controller.simulation!.deliveries, before.deliveries);
  });

  test('closing the World leaves no run', () {
    final controller = EconomySimulationController()..configure(world());

    controller.configure(null);

    expect(controller.simulation, isNull);
  });
}
