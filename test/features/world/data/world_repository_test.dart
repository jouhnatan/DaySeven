import 'dart:io';

import 'package:dayseven/features/world/data/world_repository.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late KnowledgeBase kb;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_world_repo_test');
    final bundle = Directory(p.join(temp.path, 'bundle'));
    await bundle.create();
    kb = await KnowledgeBase.create(folder: bundle.path, name: 'MyWorld');
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('round-trips Worlds and lists only world objects', () async {
    final repository = WorldRepository(kb);
    const world = World(
      id: 'world-1',
      title: 'Aster',
      dimension: WorldDimension.threeD,
      engineId: 'orogen',
    );
    const worldPath = 'Aster.unearth';
    await repository.write(worldPath, world);
    await kb.createObject(
      name: 'Third Age',
      seed: const {
        'kind': 'timeline',
        'version': 1,
        'id': 'timeline-1',
        'title': 'Third Age',
      },
    );

    final restored = await repository.read(worldPath);
    final worlds = await repository.list();

    expect(restored.id, world.id);
    expect(restored.title, world.title);
    expect(restored.engineId, world.engineId);
    expect(worlds.map((file) => file.relativePath), [worldPath]);
  });
}
