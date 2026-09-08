import 'dart:io';

import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../support/kb_harness.dart';

void main() {
  late Directory temp;

  setUp(() async {
    final dirs = await createTempDirs('dayseven_world_controller_test');
    temp = dirs.temp;
  });

  Future<(ProviderContainer, KnowledgeBase)> openWorld(
    WidgetTester tester, {
    World world = const World(id: 'world-1', title: 'Aster'),
  }) async {
    final (container, kb) = await openTestKb(tester, temp);
    late String path;
    await tester.runAsync(() async {
      path = await kb.createObject(name: 'Aster', seed: world.toJson());
      await container.read(openWorldProvider.notifier).open(path);
    });
    return (container, kb);
  }

  testWidgets('switches render mode without changing the geographic model', (
    tester,
  ) async {
    final model = DaySeven3DModel(
      landmarks: [
        Model3DLandmark(
          id: 'lm-1',
          name: 'The Spire',
          latitude: 25,
          longitude: 50,
        ),
      ],
    );
    final (container, _) = await openWorld(
      tester,
      world: World(id: 'world-1', title: 'Aster', model: model),
    );

    await container
        .read(openWorldProvider.notifier)
        .setDimension(WorldDimension.twoD);

    final world = container.read(openWorldProvider)!.world;
    expect(world.dimension, WorldDimension.twoD);
    expect(world.model!.landmarks.single.latitude, 25);
    expect(world.model!.landmarks.single.longitude, 50);
    await tester.runAsync(
      () => container.read(openWorldProvider.notifier).flush(),
    );
  });

  testWidgets('adds one source layer used by both render modes', (
    tester,
  ) async {
    final (container, _) = await openWorld(tester);
    final controller = container.read(openWorldProvider.notifier);

    controller.addModel3DLayer(
      const Model3DLayer(
        id: 'surface',
        name: 'Surface',
        type: Model3DLayerType.albedo,
        assetId: 'surface.jpg',
      ),
    );

    final model = container.read(openWorldProvider)!.world.model!;
    expect(model.layers.single.assetId, 'surface.jpg');
    expect(model.sourceMapLayerId, 'surface');
    await tester.runAsync(() => controller.flush());
  });

  testWidgets('automatically migrates legacy Orogen layers on open', (
    tester,
  ) async {
    final (container, kb) = await openTestKb(tester, temp);
    late String path;
    await tester.runAsync(() async {
      path = await kb.createObject(
        name: 'Aster',
        seed: {
          'kind': 'world',
          'version': 2,
          'id': 'world-1',
          'title': 'Aster',
          'dimension': '3d',
          'engineId': 'orogen',
          'layers': [
            {'id': 'surface', 'kind': 'satellite', 'assetId': 'surface.png'},
          ],
        },
      );
      await container.read(openWorldProvider.notifier).open(path);
      await container.read(openWorldProvider.notifier).flush();
    });

    final world = container.read(openWorldProvider)!.world;
    expect(world.model!.layers.single.id, 'surface');
    expect(world.model!.sourceMapLayerId, 'surface');
    final json = await tester.runAsync(() => kb.readObjectJson(path));
    expect(json!['version'], 3);
    expect(json['engineId'], isNull);
    expect(json['model'], isA<Map>());
  });
}
