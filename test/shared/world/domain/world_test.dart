import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/economy.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:dayseven/shared/world/domain/world_dimension.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v4 stores render mode, one shared model, and the economy', () {
    final world = World(
      id: 'world-1',
      title: 'Aster',
      dimension: WorldDimension.twoD,
      model: DaySeven3DModel(
        sourceMapLayerId: 'surface',
        layers: const [
          Model3DLayer(
            id: 'surface',
            name: 'Surface',
            type: Model3DLayerType.albedo,
            assetId: 'surface.jpg',
          ),
        ],
      ),
      economy: WorldEconomy(
        resourceTypes: const [
          ResourceType(id: 'stone', name: 'Stone', color: 'slate'),
        ],
        locations: [
          EconomyLocation(id: 'e1', landmarkId: 'aldenmoor', population: 120),
        ],
      ),
    );

    final json = world.toJson();
    final restored = World.fromJson(json);

    expect(json['version'], 4);
    expect(json['renderMode'], '2d');
    expect(json.containsKey('engineId'), isFalse);
    expect(json.containsKey('model3d'), isFalse);
    expect(restored.dimension, WorldDimension.twoD);
    expect(restored.model!.sourceMapLayerId, 'surface');
    expect(restored.model!.layers.single.assetId, 'surface.jpg');
    expect(restored.economy.locationForLandmark('aldenmoor')!.population, 120);
    expect(restored.economy.resourceType('stone')!.name, 'Stone');
  });

  test('a world with no economy writes no economy section', () {
    final json = World(id: 'world-1', title: 'Aster').toJson();
    expect(json.containsKey('economy'), isFalse);
    expect(World.fromJson(json).economy.isEmpty, isTrue);
  });

  test('wrong kind and newer versions are refused', () {
    expect(
      () => World.fromJson({'kind': 'timeline', 'version': 4}),
      throwsA(isA<WorldFormatException>()),
    );
    expect(
      () => World.fromJson({'kind': 'world', 'version': 5}),
      throwsA(isA<WorldFormatException>()),
    );
  });
}
