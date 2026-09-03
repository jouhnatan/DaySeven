import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('World version 2 schema and migration', () {
    test('reads a version 1 World Orogen file seamlessly', () {
      final v1Json = <String, Object?>{
        'kind': 'world',
        'version': 1,
        'id': 'v1-world',
        'title': 'Ancient Orogen World',
        'dimension': '3d',
        'engineId': 'orogen',
        'layers': [
          {
            'id': 'l-1',
            'kind': 'heightmap',
            'assetId': 'heightmap.png',
            'visible': true,
          },
        ],
        'engineSettings': {
          'orogen': {'planetCode': 'xyz789', 'activeLayerId': 'l-1'},
        },
      };

      final world = World.fromJson(v1Json);

      expect(world.id, 'v1-world');
      expect(world.title, 'Ancient Orogen World');
      expect(world.engineId, 'orogen');
      expect(world.layers.length, 1);
      expect(world.layers.single.assetId, 'heightmap.png');
      expect(world.engineSettings['orogen']!['planetCode'], 'xyz789');
      expect(world.model3d, isNull);
    });

    test('serializes and deserializes version 2 World with DaySeven3DModel', () {
      final model3d = DaySeven3DModel(
        geometry: const PlanetGeometry(radiusKm: 5000),
        landmarks: [
          Model3DLandmark(
            id: 'lm-1',
            name: 'Highpass',
            latitude: 12.0,
            longitude: 45.0,
          ),
        ],
      );

      final world = World(
        id: 'v2-world',
        title: 'Native 3D World',
        dimension: WorldDimension.threeD,
        engineId: WorldEngine.dayseven3D.id,
        model3d: model3d,
      );

      final json = world.toJson();
      expect(json['version'], 2);
      expect(json['engineId'], 'dayseven_3d');
      expect(json.containsKey('model3d'), isTrue);

      final restored = World.fromJson(json);
      expect(restored.engineId, 'dayseven_3d');
      expect(restored.model3d, isNotNull);
      expect(restored.model3d!.geometry.radiusKm, 5000);
      expect(restored.model3d!.landmarks.single.name, 'Highpass');
    });

    test('WorldEngine.dayseven3D is defined and orogen is deprecated', () {
      expect(WorldEngine.dayseven3D.id, 'dayseven_3d');
      expect(WorldEngine.dayseven3D.label, 'DaySeven 3D');
      expect(WorldEngine.dayseven3D.isDeprecated, isFalse);

      // ignore: deprecated_member_use_from_same_package
      expect(WorldEngine.orogen.isDeprecated, isTrue);
      // ignore: deprecated_member_use_from_same_package
      expect(WorldEngine.orogen.label, 'World Orogen');
    });
  });
}
