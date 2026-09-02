import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('layer kind ids round-trip', () {
    for (final kind in WorldLayerKind.values) {
      final layer = WorldLayer(
        id: '${kind.id}-1',
        kind: kind,
        assetId: '${kind.id}.png',
      );

      final restored = WorldLayer.fromJson(layer.toJson());

      expect(restored, isNotNull);
      expect(restored!.kind, kind);
      expect(restored.toJson(), layer.toJson());
    }
  });

  test('an unknown kind id is handled', () {
    expect(
      WorldLayer.fromJson({
        'id': 'future-1',
        'kind': 'somefuturelayer',
        'assetId': 'future.png',
      }),
      isNull,
    );
    expect(WorldLayerKind.parse('somefuturelayer'), isNull);
  });

  test('visibility defaults to true and false is stored', () {
    const hidden = WorldLayer(
      id: 'height-1',
      kind: WorldLayerKind.heightmap,
      assetId: 'height.png',
      visible: false,
    );

    expect(WorldLayer.fromJson(hidden.toJson())!.visible, isFalse);
    expect(hidden.toJson()['visible'], isFalse);
  });
}
