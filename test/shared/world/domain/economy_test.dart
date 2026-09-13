import 'package:dayseven/shared/world/domain/economy.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('economy JSON', () {
    test('round-trips types, cities, routes and nodes', () {
      final economy = WorldEconomy(
        personTypes: const [
          PersonType(id: 'p1', name: 'Soldiers', color: 'teal'),
          PersonType(id: 'p2', name: 'Bakers'),
        ],
        resourceTypes: const [
          ResourceType(id: 'stone', name: 'Stone', color: 'slate'),
          ResourceType(id: 'timber', name: 'Timber', color: 'green'),
        ],
        locations: [
          EconomyLocation(
            id: 'e1',
            landmarkId: 'aldenmoor',
            population: 900,
            personCounts: const {'p1': 40, 'p2': 0},
            resourceIds: const ['stone'],
          ),
        ],
        tradeRoutes: [
          TradeRoute(
            id: 'r1',
            fromLandmarkId: 'aldenmoor',
            toLandmarkId: 'oakhaven',
            resourceId: 'stone',
            controlPoints: const [
              [0.25, 0.4],
              [0.75, 0.6],
            ],
          ),
        ],
        resourceNodes: [
          ResourceNode(
            id: 'n1',
            resourceId: 'timber',
            latitude: 12.5,
            longitude: -3.25,
            homeLandmarkId: 'aldenmoor',
          ),
        ],
      );

      final restored = WorldEconomy.fromJson(economy.toJson());
      final location = restored.locationForLandmark('aldenmoor')!;

      expect(restored.personTypes, hasLength(2));
      expect(restored.personType('p2')!.name, 'Bakers');
      expect(location.population, 900);
      // A zero count is not a count; it is dropped on the way in.
      expect(location.personCounts, {'p1': 40});
      expect(location.resourceIds, ['stone']);
      expect(restored.tradeRoutes.single.resourceId, 'stone');
      expect(restored.tradeRoutes.single.controlPoints, [
        [0.25, 0.4],
        [0.75, 0.6],
      ]);
      expect(restored.resourceNodes.single.homeLandmarkId, 'aldenmoor');
      expect(restored.resourceNodes.single.latitude, 12.5);
    });

    test('tolerant parsing drops broken entries but keeps the good ones', () {
      final economy = WorldEconomy.fromJson({
        'personTypes': [
          {'id': 'p1', 'name': 'Soldiers'},
          {'id': '', 'name': 'Nameless'},
        ],
        'locations': [
          {'id': 'e1', 'landmarkId': 'city'},
          {'id': 'e2'},
        ],
        'tradeRoutes': [
          {'id': 'r1', 'from': 'city', 'to': 'city'},
          {'id': 'r2', 'from': 'city', 'to': 'other'},
        ],
        'resourceNodes': [
          {'id': 'n1', 'resourceId': 'stone', 'latitude': 400, 'longitude': 0},
        ],
      });

      expect(economy.personTypes, hasLength(1));
      expect(economy.locations, hasLength(1));
      // A route from a city to itself is not a route.
      expect(economy.tradeRoutes.single.id, 'r2');
      // Coordinates outside the globe clamp to it.
      expect(economy.resourceNodes.single.latitude, 90);
    });
  });

  group('economy edits', () {
    WorldEconomy seeded() => WorldEconomy.seeded();

    test('deleting a person type removes it from every city', () {
      final economy = seeded().withPersonType(
        const PersonType(id: 'p1', name: 'Farmers'),
      ).withLocation(
        EconomyLocation(
          id: 'e1',
          landmarkId: 'city',
          personCounts: const {'p1': 12},
        ),
      );

      final without = economy.withoutPersonType('p1');
      expect(without.personTypes, isEmpty);
      expect(without.locations.single.personCounts, isEmpty);
    });

    test('deleting a resource type clears cities, nodes and routes', () {
      final economy = seeded();
      final withEverything = economy
          .withLocation(
            EconomyLocation(
              id: 'e1',
              landmarkId: 'city',
              resourceIds: const ['stone', 'gold'],
            ),
          )
          .withResourceNode(
            ResourceNode(
              id: 'n1',
              resourceId: 'stone',
              latitude: 0,
              longitude: 0,
            ),
          )
          .withTradeRoute(
            TradeRoute(
              id: 'r1',
              fromLandmarkId: 'city',
              toLandmarkId: 'other',
              resourceId: 'stone',
            ),
          );

      final without = withEverything.withoutResourceType('stone');
      expect(without.resourceType('stone'), isNull);
      expect(without.locations.single.resourceIds, ['gold']);
      expect(without.resourceNodes, isEmpty);
      expect(without.tradeRoutes.single.resourceId, isNull);
    });

    test('deleting a landmark removes its profile, routes and nodes', () {
      final economy = seeded()
          .withLocation(EconomyLocation(id: 'e1', landmarkId: 'city'))
          .withLocation(EconomyLocation(id: 'e2', landmarkId: 'other'))
          .withResourceNode(
            ResourceNode(
              id: 'n1',
              resourceId: 'stone',
              latitude: 0,
              longitude: 0,
              homeLandmarkId: 'city',
            ),
          )
          .withResourceNode(
            ResourceNode(
              id: 'n2',
              resourceId: 'stone',
              latitude: 1,
              longitude: 1,
              homeLandmarkId: 'other',
            ),
          )
          .withTradeRoute(
            TradeRoute(
              id: 'r1',
              fromLandmarkId: 'city',
              toLandmarkId: 'other',
            ),
          );

      final without = economy.withoutLandmark('city');
      expect(without.locationForLandmark('city'), isNull);
      expect(without.resourceNodes.single.homeLandmarkId, 'other');
      expect(without.tradeRoutes, isEmpty);
    });

    test('withLocation replaces a landmark profile rather than duplicating it',
        () {
      var economy = seeded().withLocation(
        EconomyLocation(id: 'e1', landmarkId: 'city', population: 10),
      );
      economy = economy.withLocation(
        EconomyLocation(id: 'e1', landmarkId: 'city', population: 99),
      );
      expect(economy.locations, hasLength(1));
      expect(economy.locations.single.population, 99);
    });
  });

  group('format migration', () {
    test('a version 3 world gains the three built-in resources', () {
      final world = World.fromJson({
        'kind': 'world',
        'version': 3,
        'id': 'legacy',
        'title': 'Legacy',
      });

      expect(world.economy.resourceTypes.map((type) => type.name), [
        'Stone',
        'Timber',
        'Gold',
      ]);
      expect(world.requiresMigration, isTrue);
      expect(world.toJson()['version'], 4);
    });

    test('a version 4 world with an emptied economy stays empty', () {
      final world = World.fromJson({
        'kind': 'world',
        'version': 4,
        'id': 'current',
        'title': 'Current',
        'economy': <String, Object?>{},
      });

      expect(world.economy.isEmpty, isTrue);
      expect(world.requiresMigration, isFalse);
    });
  });
}
