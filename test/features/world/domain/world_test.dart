import 'dart:convert';

import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/features/world/domain/world_metadata.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  World sample() => const World(
    id: 'world-1',
    title: 'Aster',
    dimension: WorldDimension.threeD,
    engineId: 'orogen',
    layers: [
      WorldLayer(
        id: 'satellite-1',
        kind: WorldLayerKind.satellite,
        assetId: 'satellite.png',
        metadata: WorldMetadata(
          width: 4096,
          height: 2048,
          isGreyscale: false,
          planetCode: 'abc123',
          textChunks: {'Software': 'World Orogen'},
        ),
      ),
    ],
    engineSettings: {
      'orogen': {'planetCode': 'abc123', 'activeLayerId': 'satellite-1'},
    },
  );

  test('a world survives being written and read back', () {
    final restored = World.fromJson(sample().toJson());

    expect(restored.id, 'world-1');
    expect(restored.title, 'Aster');
    expect(restored.dimension, WorldDimension.threeD);
    expect(restored.engineId, 'orogen');
    expect(restored.layers.single.kind, WorldLayerKind.satellite);
    expect(restored.layers.single.assetId, 'satellite.png');
    expect(restored.layers.single.metadata!.isEquirectangular, isTrue);
    expect(restored.engineSettings['orogen']!['planetCode'], 'abc123');
  });

  test('the envelope names the kind and the version', () {
    final json = sample().toJson();

    expect(json['kind'], 'world');
    expect(json['version'], 1);
  });

  test('wrong kind is refused', () {
    expect(
      () => World.fromJson({'kind': 'timeline', 'version': 1}),
      throwsA(isA<WorldFormatException>()),
    );
  });

  test('a newer version is refused', () {
    expect(
      () => World.fromJson({'kind': 'world', 'version': 2}),
      throwsA(isA<WorldFormatException>()),
    );
  });

  test('missing optional fields are tolerated', () {
    final world = World.fromJson({
      'kind': 'world',
      'version': 1,
      'id': 'empty',
      'title': 'Empty',
    });

    expect(world.dimension, WorldDimension.threeD);
    expect(world.engineId, isNull);
    expect(world.layers, isEmpty);
    expect(world.engineSettings, isEmpty);
    expect(world.toJson().containsKey('engineId'), isFalse);
    expect(world.toJson().containsKey('layers'), isFalse);
    expect(world.toJson().containsKey('engineSettings'), isFalse);
  });

  test('unknown engine settings survive byte-identically', () {
    final futureSettings = <String, Object?>{
      'planetCode': 'future-1',
      'options': [
        'kept',
        {'nested': true},
      ],
    };
    final source = <String, Object?>{
      'kind': 'world',
      'version': 1,
      'id': 'future',
      'title': 'Future',
      'engineSettings': <String, Object?>{'somefutureengine': futureSettings},
    };

    final restored = World.fromJson(source);
    final written = restored.toJson()['engineSettings'];

    expect(jsonEncode(written), jsonEncode(source['engineSettings']));
  });

  test('copyWith can clear the engine id', () {
    expect(sample().copyWith(clearEngineId: true).engineId, isNull);
  });
}
