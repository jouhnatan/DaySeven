import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:dayseven/shared/world/domain/world_dimension.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('v3 stores render mode and one shared geographic model', () {
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
    );

    final json = world.toJson();
    final restored = World.fromJson(json);

    expect(json['version'], 3);
    expect(json['renderMode'], '2d');
    expect(json.containsKey('engineId'), isFalse);
    expect(json.containsKey('model3d'), isFalse);
    expect(restored.dimension, WorldDimension.twoD);
    expect(restored.model!.sourceMapLayerId, 'surface');
    expect(restored.model!.layers.single.assetId, 'surface.jpg');
  });

  test('wrong kind and newer versions are refused', () {
    expect(
      () => World.fromJson({'kind': 'timeline', 'version': 3}),
      throwsA(isA<WorldFormatException>()),
    );
    expect(
      () => World.fromJson({'kind': 'world', 'version': 4}),
      throwsA(isA<WorldFormatException>()),
    );
  });
}
