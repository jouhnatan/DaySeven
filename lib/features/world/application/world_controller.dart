/// The World currently open: its contents, whether it has unsaved changes,
/// and the debounced save that follows an edit.
///
/// This is the World sibling of `TimelineController`. Both are objects stored
/// in the Knowledge Base, so they deliberately share the open-edit-debounce-
/// save shape rather than making each view invent its own lifecycle.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/world/application/world_engine_registry.dart';
import 'package:dayseven/features/world/data/world_repository.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class OpenWorld {
  const OpenWorld({
    required this.relativePath,
    required this.world,
    required this.dirty,
  });

  final String relativePath;
  final World world;

  /// True between an edit and the debounced save that follows it.
  final bool dirty;

  OpenWorld copyWith({String? relativePath, World? world, bool? dirty}) =>
      OpenWorld(
        relativePath: relativePath ?? this.relativePath,
        world: world ?? this.world,
        dirty: dirty ?? this.dirty,
      );
}

class WorldController extends StateNotifier<OpenWorld?> {
  WorldController(this._ref) : super(null);

  final Ref _ref;
  Timer? _saveDebounce;
  int _openGeneration = 0;

  // World and Timeline use the same delay on purpose: both are object files
  // whose edits should settle before the next write reaches disk.
  static const _saveDelay = Duration(milliseconds: 600);
  static const _engineRegistry = WorldEngineRegistry();

  Future<void> open(String relativePath) async {
    final generation = ++_openGeneration;
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;

    await flush();
    if (!mounted || generation != _openGeneration) return;

    final stored = await WorldRepository(session.kb).read(relativePath);
    if (!mounted || generation != _openGeneration) return;

    // The file name is the name: the same rule documents and timelines follow,
    // so renaming the object never leaves two names to reconcile.
    final fileName = objectNameFromPath(relativePath);
    final world = stored.title == fileName
        ? stored
        : stored.copyWith(title: fileName);
    state = OpenWorld(relativePath: relativePath, world: world, dirty: false);
  }

  void close({bool save = true}) {
    _openGeneration++;
    if (save) {
      unawaited(flush());
    } else {
      _saveDebounce?.cancel();
    }
    state = null;
  }

  /// Applies an edit and schedules a save, so layer and engine changes cannot
  /// bypass dirty tracking.
  void edit(World next) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(world: next, dirty: true);

    _saveDebounce?.cancel();
    _saveDebounce = Timer(_saveDelay, () {
      unawaited(flush());
    });
  }

  /// Updates the open path after the object has been renamed or moved.
  void relocate(String newPath) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(relativePath: newPath);
  }

  /// Forgets the open World when the file behind it is gone.
  void closeIfOpen(String path) {
    final current = state;
    if (current == null) return;
    if (current.relativePath != path &&
        !current.relativePath.startsWith('$path/')) {
      return;
    }
    _saveDebounce?.cancel();
    _openGeneration++;
    state = null;
  }

  /// Writes the open World to disk.
  Future<void> flush() async {
    _saveDebounce?.cancel();
    final current = state;
    final session = _ref.read(kbSessionProvider);
    if (current == null || session == null || !current.dirty) return;

    await WorldRepository(session.kb)
        .write(current.relativePath, current.world);
    // An edit may have arrived while the disk write was in flight. Only the
    // exact snapshot that was written becomes clean.
    if (mounted && identical(state, current)) {
      state = current.copyWith(dirty: false);
    }
  }

  /// Adds [layer] to the open World.
  void addLayer(WorldLayer layer) {
    final current = state;
    if (current == null) return;
    edit(current.world.copyWith(layers: [...current.world.layers, layer]));
  }

  /// Removes a layer reference without removing its asset file.
  void removeLayer(String layerId) {
    final current = state;
    if (current == null) return;
    final layers = current.world.layers
        .where((layer) => layer.id != layerId)
        .toList();
    if (layers.length == current.world.layers.length) return;

    // Clearing a reference is not a reason to delete somebody's picture; the
    // asset remains in `.settings/assets/`, just as timeline map assets do.
    edit(current.world.copyWith(layers: layers));
  }

  /// Changes the visibility flag of one layer.
  void setLayerVisible(String layerId, bool visible) {
    final current = state;
    if (current == null) return;
    final layers = [...current.world.layers];
    final index = layers.indexWhere((layer) => layer.id == layerId);
    if (index < 0 || layers[index].visible == visible) return;

    final layer = layers[index];
    layers[index] = WorldLayer(
      id: layer.id,
      kind: layer.kind,
      assetId: layer.assetId,
      metadata: layer.metadata,
      visible: visible,
    );
    edit(current.world.copyWith(layers: layers));
  }

  /// Chooses the engine id stored on the open World.
  void setEngine(String engineId) {
    final current = state;
    if (current == null) return;
    edit(current.world.copyWith(engineId: engineId));
  }

  /// Changes dimension, clearing an engine that cannot exist in the new one.
  void setDimension(WorldDimension dimension) {
    final current = state;
    if (current == null) return;
    final hasEngines = _engineRegistry.enginesFor(dimension).isNotEmpty;
    edit(
      current.world.copyWith(dimension: dimension, clearEngineId: !hasEngines),
    );
  }

  /// Replaces one engine's raw settings without discarding unknown fields.
  void updateEngineSettings(String engineId, Map<String, Object?> settings) {
    final current = state;
    if (current == null) return;
    final engineSettings = <String, Map<String, Object?>>{
      ...current.world.engineSettings,
      engineId: Map<String, Object?>.from(settings),
    };
    edit(current.world.copyWith(engineSettings: engineSettings));
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}
