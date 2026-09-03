/// Reads and writes Worlds as `.unearth` objects in a Knowledge Base.
library;

import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/shared/kb/bundle.dart';

/// The World feature's kind-aware edge around the generic object store.
class WorldRepository {
  WorldRepository(this.kb);

  final KnowledgeBase kb;

  /// Lists only World objects; [KnowledgeBase.readObjects] is intentionally
  /// kind-blind so that this filter remains with the feature that owns it.
  Future<List<KbFile>> list() async {
    final objects = await kb.readObjects();
    final worlds = <KbFile>[];
    for (final object in objects) {
      final json = await kb.readObjectJson(object.relativePath);
      if (json['kind'] == World.kind) worlds.add(object);
    }
    return worlds;
  }

  /// Reads and validates one World object at [relativePath].
  Future<World> read(String relativePath) async =>
      World.fromJson(await kb.readObjectJson(relativePath));

  /// Writes [world] to the existing or new object path [relativePath].
  Future<void> write(String relativePath, World world) =>
      kb.writeObjectJson(relativePath, world.toJson());
}
