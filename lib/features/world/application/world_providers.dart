/// Riverpod state for the World view and its open object.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_engine_registry.dart';
import 'package:dayseven/features/world/data/world_asset_repository.dart';
import 'package:dayseven/features/world/data/world_repository.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_engine.dart';
import 'package:dayseven/shared/kb/bundle.dart';

const _worldEngineRegistry = WorldEngineRegistry();

/// The repository for the currently open Knowledge Base.
final worldRepositoryProvider = Provider<WorldRepository>((ref) {
  final session = ref.watch(kbSessionProvider);
  if (session == null) {
    throw StateError('Open a Knowledge Base before reading World objects.');
  }
  return WorldRepository(session.kb);
});

/// The World layer asset repository for the currently open Knowledge Base.
final worldAssetRepositoryProvider = Provider<WorldAssetRepository>((ref) {
  final session = ref.watch(kbSessionProvider);
  if (session == null) {
    throw StateError('Open a Knowledge Base before importing World layers.');
  }
  return WorldAssetRepository(session.kb);
});

/// The World object currently open in the centre workspace.
final openWorldProvider = StateNotifierProvider<WorldController, OpenWorld?>(
  WorldController.new,
);

/// The World objects in the open Knowledge Base.
final worldObjectsProvider = FutureProvider<List<KbFile>>((ref) async {
  final session = ref.watch(kbSessionProvider);
  if (session == null) return const [];
  return ref.watch(worldRepositoryProvider).list();
});

/// The dimension selected in the World settings pane.
final selectedWorldDimensionProvider = StateProvider<WorldDimension>(
  (ref) => WorldDimension.threeD,
);

/// The engines available to the selected World dimension.
final availableEnginesProvider = Provider<List<WorldEngine>>((ref) {
  final dimension = ref.watch(selectedWorldDimensionProvider);
  return _worldEngineRegistry.enginesFor(dimension);
});

/// The known engine behind the open World's stored engine id, if any.
final activeWorldEngineProvider = Provider<WorldEngine?>((ref) {
  final open = ref.watch(openWorldProvider);
  return _worldEngineRegistry.byId(open?.world.engineId);
});

/// Whether the 3D globe is in "drop pin" mode for placing landmark pins.
final dropPinModeProvider = StateProvider<bool>((ref) => false);
