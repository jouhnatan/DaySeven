import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates v2 Orogen layers into the shared model', () {
    final world = World.fromJson({
      'kind': 'world',
      'version': 2,
      'id': 'legacy',
      'title': 'Legacy',
      'dimension': '3d',
      'engineId': 'orogen',
      'layers': [
        {'id': 'surface', 'kind': 'satellite', 'assetId': 'surface.png'},
        {'id': 'height', 'kind': 'heightmap', 'assetId': 'height.png'},
      ],
    });

    expect(world.model!.layers, hasLength(2));
    expect(world.model!.layers.first.type, Model3DLayerType.albedo);
    expect(world.model!.sourceMapLayerId, 'surface');
    expect(world.toJson().containsKey('engineId'), isFalse);
    expect(world.toJson().containsKey('layers'), isFalse);
  });
}
