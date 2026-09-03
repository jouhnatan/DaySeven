import 'dart:io';

import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/data/world_repository.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
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

  Future<void> settleSaves(
    WidgetTester tester,
    ProviderContainer container,
  ) async {
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => container.read(openWorldProvider.notifier).flush(),
    );
  }

  testWidgets('opens, edits, marks dirty, and flushes a World', (tester) async {
    final (container, kb) = await openWorld(tester);
    final controller = container.read(openWorldProvider.notifier);
    final open = container.read(openWorldProvider)!;

    expect(open.world.title, 'Aster');
    expect(open.dirty, isFalse);

    controller.edit(open.world.copyWith(title: 'Changed'));

    expect(container.read(openWorldProvider)!.dirty, isTrue);
    await tester.runAsync(() => controller.flush());
    late World restored;
    await tester.runAsync(() async {
      restored = World.fromJson(await kb.readObjectJson('Aster.unearth'));
    });

    expect(restored.title, 'Changed');
    expect(container.read(openWorldProvider)!.dirty, isFalse);
  });

  testWidgets('switching to a dimension with no engines clears engine id', (
    tester,
  ) async {
    final (container, _) = await openWorld(
      tester,
      world: const World(id: 'world-1', title: 'Aster', engineId: 'orogen'),
    );
    final controller = container.read(openWorldProvider.notifier);

    controller.setDimension(WorldDimension.twoD);

    expect(
      container.read(openWorldProvider)!.world.dimension,
      WorldDimension.twoD,
    );
    expect(container.read(openWorldProvider)!.world.engineId, isNull);
    await tester.runAsync(
      () => container.read(openWorldProvider.notifier).flush(),
    );
  });

  testWidgets('removing a layer leaves its asset file on disk', (tester) async {
    const assetId = 'heightmap.png';
    final (container, kb) = await openWorld(
      tester,
      world: const World(
        id: 'world-1',
        title: 'Aster',
        layers: [
          WorldLayer(
            id: 'heightmap-1',
            kind: WorldLayerKind.heightmap,
            assetId: assetId,
          ),
        ],
      ),
    );
    final asset = File(kb.assetPathFor(assetId));
    await tester.runAsync(() => asset.writeAsBytes([1, 2, 3]));
    final controller = container.read(openWorldProvider.notifier);

    controller.removeLayer('heightmap-1');
    await tester.runAsync(() => controller.flush());

    expect(container.read(openWorldProvider)!.world.layers, isEmpty);
    expect(asset.existsSync(), isTrue);
  });

  testWidgets('edit becomes a matching disk write after the debounce', (
    tester,
  ) async {
    final (container, kb) = await openWorld(tester);
    final controller = container.read(openWorldProvider.notifier);

    controller.edit(
      container
          .read(openWorldProvider)!
          .world
          .copyWith(title: 'After debounce'),
    );
    expect(container.read(openWorldProvider)!.dirty, isTrue);

    await settleSaves(tester, container);
    late World restored;
    await tester.runAsync(() async {
      restored = World.fromJson(await kb.readObjectJson('Aster.unearth'));
    });

    expect(restored.title, 'After debounce');
    expect(container.read(openWorldProvider)!.dirty, isFalse);
  });

  testWidgets(
    'setEngine creates and opens a new World on disk when none exists',
    (tester) async {
      final (container, kb) = await openTestKb(tester, temp, name: 'Awayside');
      final controller = container.read(openWorldProvider.notifier);

      expect(container.read(openWorldProvider), isNull);

      await tester.runAsync(() => controller.setEngine('orogen'));

      final open = container.read(openWorldProvider);
      expect(open, isNotNull);
      expect(open!.world.title, 'Awayside');
      expect(open.world.engineId, 'orogen');
      expect(open.relativePath, 'Awayside.unearth');

      final repo = WorldRepository(kb);
      final worlds = await tester.runAsync(() => repo.list());
      expect(worlds!.map((f) => f.relativePath), ['Awayside.unearth']);
    },
  );

  testWidgets('loadExisting opens an existing world in the Knowledge Base', (
    tester,
  ) async {
    final (container, kb) = await openTestKb(tester, temp, name: 'Awayside');
    await tester.runAsync(() async {
      await kb.createObject(
        name: 'Awayside',
        seed: const World(
          id: 'world-1',
          title: 'Awayside',
          engineId: 'orogen',
        ).toJson(),
      );
    });

    final controller = container.read(openWorldProvider.notifier);
    expect(container.read(openWorldProvider), isNull);

    await tester.runAsync(() => controller.loadExisting());

    final open = container.read(openWorldProvider);
    expect(open, isNotNull);
    expect(open!.world.title, 'Awayside');
    expect(open.world.engineId, 'orogen');
  });

  testWidgets('migrateOrogenToDaySeven3D converts layers and sets engineId', (
    tester,
  ) async {
    final (container, kb) = await openWorld(
      tester,
      world: const World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'orogen',
        layers: [
          WorldLayer(
            id: 'l-1',
            kind: WorldLayerKind.heightmap,
            assetId: 'heightmap.png',
            visible: true,
          ),
        ],
      ),
    );
    final controller = container.read(openWorldProvider.notifier);

    controller.migrateOrogenToDaySeven3D();

    final open = container.read(openWorldProvider)!;
    expect(open.world.engineId, 'dayseven_3d');
    expect(open.world.model3d, isNotNull);
    expect(open.world.model3d!.layers.length, 1);
    expect(open.world.model3d!.layers.first.id, 'l-1');
    expect(
      open.world.model3d!.layers.first.type,
      Model3DLayerType.heightmap,
    );
    expect(open.world.model3d!.layers.first.assetId, 'heightmap.png');
    await settleSaves(tester, container);
  });

  testWidgets('manages landmarks and 3D layers on open world', (tester) async {
    final (container, kb) = await openWorld(tester);
    final controller = container.read(openWorldProvider.notifier);

    controller.addLandmark(
      Model3DLandmark(
        id: 'lm-1',
        name: 'The Spire',
        latitude: 25.0,
        longitude: 50.0,
      ),
    );

    expect(
      container.read(openWorldProvider)!.world.model3d!.landmarks.length,
      1,
    );

    controller.updateLandmark(
      Model3DLandmark(
        id: 'lm-1',
        name: 'The Grand Spire',
        latitude: 25.0,
        longitude: 50.0,
      ),
    );
    expect(
      container
          .read(openWorldProvider)!
          .world
          .model3d!
          .landmarks
          .first
          .name,
      'The Grand Spire',
    );

    controller.addModel3DLayer(
      const Model3DLayer(
        id: 'layer-albedo',
        name: 'Colors',
        type: Model3DLayerType.albedo,
        assetId: 'colors.png',
      ),
    );
    expect(
      container.read(openWorldProvider)!.world.model3d!.layers.length,
      1,
    );

    controller.setModel3DLayerOpacity('layer-albedo', 0.7);
    expect(
      container
          .read(openWorldProvider)!
          .world
          .model3d!
          .layers
          .first
          .opacity,
      0.7,
    );

    controller.removeLandmark('lm-1');
    expect(
      container.read(openWorldProvider)!.world.model3d!.landmarks,
      isEmpty,
    );

    controller.removeModel3DLayer('layer-albedo');
    expect(container.read(openWorldProvider)!.world.model3d!.layers, isEmpty);
    await settleSaves(tester, container);
  });

  testWidgets('migration is idempotent on repeated calls', (tester) async {
    final (container, kb) = await openWorld(
      tester,
      world: const World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'orogen',
        layers: [
          WorldLayer(
            id: 'l-1',
            kind: WorldLayerKind.heightmap,
            assetId: 'heightmap.png',
            visible: true,
          ),
        ],
      ),
    );
    final controller = container.read(openWorldProvider.notifier);

    controller.migrateOrogenToDaySeven3D();
    controller.migrateOrogenToDaySeven3D();

    final open = container.read(openWorldProvider)!;
    expect(open.world.model3d!.layers.length, 1);
    await settleSaves(tester, container);
  });

  testWidgets('switching from 2D to 3D automatically selects DaySeven 3D', (
    tester,
  ) async {
    final (container, kb) = await openWorld(
      tester,
      world: const World(
        id: 'world-2d',
        title: 'Flatland',
        dimension: WorldDimension.twoD,
      ),
    );
    final controller = container.read(openWorldProvider.notifier);

    await controller.setDimension(WorldDimension.threeD);

    final open = container.read(openWorldProvider)!;
    expect(open.world.dimension, WorldDimension.threeD);
    expect(open.world.engineId, 'dayseven_3d');
    await settleSaves(tester, container);
  });
}
