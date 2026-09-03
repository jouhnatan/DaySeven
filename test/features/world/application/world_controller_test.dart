import 'dart:io';

import 'package:dayseven/features/world/application/world_providers.dart';
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
}
