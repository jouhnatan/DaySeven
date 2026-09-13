/// Riverpod state for the World view and its open object.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/world_controller.dart';
import 'package:dayseven/shared/world/data/world_asset_repository.dart';
import 'package:dayseven/shared/world/data/world_repository.dart';
import 'package:dayseven/shared/world/domain/world_dimension.dart';

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

/// The dimension selected in the World settings pane.
final selectedWorldDimensionProvider = StateProvider<WorldDimension>(
  (ref) => WorldDimension.threeD,
);
