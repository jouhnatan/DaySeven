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
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/data/world_repository.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_engine.dart';
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
    _ref.read(selectedWorldDimensionProvider.notifier).state = world.dimension;
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

  /// Updates the 3D model metadata on the open World.
  void updateModel3D(DaySeven3DModel next) {
    final current = state;
    if (current == null) return;
    edit(current.world.copyWith(model3d: next));
  }

  /// Migrates an existing World Orogen world to DaySeven 3D.
  void migrateOrogenToDaySeven3D() {
    final current = state;
    if (current == null) return;

    final existingModel = current.world.model3d;
    final existingLayers = existingModel?.layers ?? const <Model3DLayer>[];
    final existingIds = {for (final l in existingLayers) l.id};

    final convertedLayers = <Model3DLayer>[
      ...existingLayers,
      for (final layer in current.world.layers)
        if (!existingIds.contains(layer.id))
          Model3DLayer(
            id: layer.id,
            name: switch (layer.kind) {
              WorldLayerKind.heightmap => 'Elevation (Heightmap)',
              WorldLayerKind.landHeightmap => 'Land Elevation',
              WorldLayerKind.satellite => 'Surface Color (Satellite)',
              WorldLayerKind.climate => 'Climate Map',
              WorldLayerKind.landMask => 'Land Mask',
            },
            type: switch (layer.kind) {
              WorldLayerKind.heightmap ||
              WorldLayerKind.landHeightmap => Model3DLayerType.heightmap,
              WorldLayerKind.satellite => Model3DLayerType.albedo,
              WorldLayerKind.climate => Model3DLayerType.biomes,
              WorldLayerKind.landMask => Model3DLayerType.specular,
            },
            assetId: layer.assetId,
            visible: layer.visible,
          ),
    ];

    final updatedModel = (existingModel ?? DaySeven3DModel()).copyWith(
      layers: convertedLayers,
    );

    edit(
      current.world.copyWith(
        engineId: WorldEngine.dayseven3D.id,
        model3d: updatedModel,
      ),
    );
  }

  /// Adds [layer] to the 3D model stack.
  void addModel3DLayer(Model3DLayer layer) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d ?? DaySeven3DModel();
    final updated = model.copyWith(layers: [...model.layers, layer]);
    edit(current.world.copyWith(model3d: updated));
  }

  /// Removes [layerId] from the 3D model stack.
  void removeModel3DLayer(String layerId) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d;
    if (model == null) return;
    final layers = model.layers.where((l) => l.id != layerId).toList();
    if (layers.length == model.layers.length) return;
    edit(current.world.copyWith(model3d: model.copyWith(layers: layers)));
  }

  /// Changes the visibility of a 3D model texture layer.
  void setModel3DLayerVisible(String layerId, bool visible) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d;
    if (model == null) return;
    final layers = [...model.layers];
    final index = layers.indexWhere((l) => l.id == layerId);
    if (index < 0 || layers[index].visible == visible) return;

    layers[index] = layers[index].copyWith(visible: visible);
    edit(current.world.copyWith(model3d: model.copyWith(layers: layers)));
  }

  /// Changes the opacity of a 3D model texture layer.
  void setModel3DLayerOpacity(String layerId, double opacity) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d;
    if (model == null) return;
    final layers = [...model.layers];
    final index = layers.indexWhere((l) => l.id == layerId);
    if (index < 0 || layers[index].opacity == opacity) return;

    layers[index] = layers[index].copyWith(opacity: opacity.clamp(0.0, 1.0));
    edit(current.world.copyWith(model3d: model.copyWith(layers: layers)));
  }

  /// Adds a landmark pin to the 3D model.
  void addLandmark(Model3DLandmark landmark) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d ?? DaySeven3DModel();
    final updated = model.copyWith(landmarks: [...model.landmarks, landmark]);
    edit(current.world.copyWith(model3d: updated));
  }

  /// Removes a landmark pin from the 3D model.
  void removeLandmark(String landmarkId) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d;
    if (model == null) return;
    final landmarks =
        model.landmarks.where((lm) => lm.id != landmarkId).toList();
    if (landmarks.length == model.landmarks.length) return;
    edit(current.world.copyWith(model3d: model.copyWith(landmarks: landmarks)));
  }

  /// Updates an existing landmark pin in the 3D model.
  void updateLandmark(Model3DLandmark landmark) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d;
    if (model == null) return;
    final landmarks = [...model.landmarks];
    final index = landmarks.indexWhere((lm) => lm.id == landmark.id);
    if (index < 0) return;
    landmarks[index] = landmark;
    edit(current.world.copyWith(model3d: model.copyWith(landmarks: landmarks)));
  }

  /// Opens the first World in the Knowledge Base if one exists and none is open.
  Future<void> loadExisting() async {
    if (state != null) return;
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;

    final repo = WorldRepository(session.kb);
    final worlds = await repo.list();
    if (worlds.isNotEmpty && mounted && state == null) {
      await open(worlds.first.relativePath);
    }
  }

  /// Chooses the engine id stored on the open World.
  ///
  /// If no World is currently open, loads an existing World from the Knowledge
  /// Base or creates a new one so that engine selection immediately takes effect.
  Future<void> setEngine(String engineId) async {
    final current = state;
    if (current != null) {
      edit(current.world.copyWith(engineId: engineId));
      return;
    }
    await _ensureOpen(engineId: engineId);
  }

  /// Changes dimension, clearing an engine that cannot exist in the new one.
  ///
  /// If no World is currently open, loads an existing World from the Knowledge
  /// Base or creates a new one so that dimension selection immediately takes effect.
  Future<void> setDimension(WorldDimension dimension) async {
    final current = state;
    if (current != null) {
      final availableEngines = _engineRegistry.enginesFor(dimension);
      final hasEngines = availableEngines.isNotEmpty;
      final currentEngineValid =
          availableEngines.any((e) => e.id == current.world.engineId);
      final nextEngineId = currentEngineValid
          ? current.world.engineId
          : (hasEngines ? _engineRegistry.defaultFor(dimension)?.id : null);
      edit(
        current.world.copyWith(
          dimension: dimension,
          engineId: nextEngineId,
          clearEngineId: !hasEngines,
        ),
      );
      return;
    }
    await _ensureOpen(dimension: dimension);
  }

  /// Ensures a World is open by loading an existing one from the Knowledge Base
  /// or creating a new one if none exists yet.
  Future<void> _ensureOpen({
    String? engineId,
    WorldDimension? dimension,
  }) async {
    final session = _ref.read(kbSessionProvider);
    final WorldDimension targetDimension =
        dimension ?? _ref.read(selectedWorldDimensionProvider);
    final effectiveEngineId =
        engineId ?? _engineRegistry.defaultFor(targetDimension)?.id;

    if (session == null) {
      final world = World(
        id: newId(),
        title: 'World',
        dimension: targetDimension,
        engineId: effectiveEngineId,
      );
      state = OpenWorld(
        relativePath: 'World$kObjectExtension',
        world: world,
        dirty: false,
      );
      _ref.read(selectedWorldDimensionProvider.notifier).state =
          targetDimension;
      return;
    }

    final repo = WorldRepository(session.kb);
    final worlds = await repo.list();
    if (!mounted) return;

    if (worlds.isNotEmpty) {
      await open(worlds.first.relativePath);
      if (mounted && state != null) {
        var world = state!.world;
        if (dimension != null) {
          final hasEngines =
              _engineRegistry.enginesFor(dimension).isNotEmpty;
          world = world.copyWith(
            dimension: dimension,
            clearEngineId: !hasEngines,
          );
        }
        if (engineId != null) {
          world = world.copyWith(engineId: engineId);
        }
        if (world != state!.world) {
          edit(world);
        }
      }
    } else {
      final name = session.kb.manifest.name.isNotEmpty
          ? session.kb.manifest.name
          : 'World';
      final relativePath = await session.kb.createObject(
        name: name,
        seed: World(
          id: newId(),
          title: name,
          dimension: targetDimension,
          engineId: effectiveEngineId,
        ).toJson(),
      );
      if (!mounted) return;
      await open(relativePath);
    }
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
