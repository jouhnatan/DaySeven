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
import 'package:dayseven/app/workspace/world_providers.dart';
import 'package:dayseven/shared/world/data/world_repository.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:dayseven/shared/world/domain/world_dimension.dart';
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
    final needsMigration =
        stored.requiresMigration ||
        stored.engineId != null ||
        stored.layers.isNotEmpty ||
        stored.engineSettings.isNotEmpty;
    state = OpenWorld(
      relativePath: relativePath,
      world: world,
      dirty: needsMigration,
    );
    _ref.read(selectedWorldDimensionProvider.notifier).state = world.dimension;
    if (needsMigration) await flush();
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
      state = current.copyWith(
        world: current.world.copyWith(requiresMigration: false),
        dirty: false,
      );
    }
  }

  /// Updates the geographic model shared by both render modes.
  void updateModel3D(DaySeven3DModel next) {
    final current = state;
    if (current == null) return;
    edit(current.world.copyWith(model: next));
  }

  /// Adds [layer] to the 3D model stack.
  void addModel3DLayer(Model3DLayer layer) {
    final current = state;
    if (current == null) return;
    final model = current.world.model ?? DaySeven3DModel();
    final updated = model.copyWith(
      layers: [...model.layers, layer],
      sourceMapLayerId: model.sourceMapLayerId ?? layer.id,
    );
    edit(current.world.copyWith(model: updated));
  }

  /// Makes [layer] the one source map shared by the 2D and 3D renderers.
  ///
  /// Existing imported assets remain referenced so migration never destroys
  /// data, but only this layer is presented as the source map in the UI.
  void setSourceMapLayer(Model3DLayer layer) {
    final current = state;
    if (current == null) return;
    final model = current.world.model ?? DaySeven3DModel();
    edit(
      current.world.copyWith(
        model: model.copyWith(
          layers: [...model.layers, layer],
          sourceMapLayerId: layer.id,
        ),
      ),
    );
  }

  /// Removes [layerId] from the 3D model stack.
  void removeModel3DLayer(String layerId) {
    final current = state;
    if (current == null) return;
    final model = current.world.model3d;
    if (model == null) return;
    final layers = model.layers.where((l) => l.id != layerId).toList();
    if (layers.length == model.layers.length) return;
    final removedSource = model.sourceMapLayerId == layerId;
    edit(
      current.world.copyWith(
        model: model.copyWith(
          layers: layers,
          sourceMapLayerId: removedSource && layers.isNotEmpty
              ? layers.last.id
              : model.sourceMapLayerId,
          clearSourceMapLayerId: removedSource && layers.isEmpty,
        ),
      ),
    );
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
    final landmarks = model.landmarks
        .where((lm) => lm.id != landmarkId)
        .toList();
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

  /// Changes how the same geographic model is rendered.
  ///
  /// If no World is currently open, loads an existing World from the Knowledge
  /// Base or creates a new one so that dimension selection immediately takes effect.
  Future<void> setDimension(WorldDimension dimension) async {
    final current = state;
    if (current != null) {
      edit(current.world.copyWith(dimension: dimension));
      return;
    }
    await _ensureOpen(dimension: dimension);
  }

  /// Ensures a World is open by loading an existing one from the Knowledge Base
  /// or creating a new one if none exists yet.
  Future<void> _ensureOpen({WorldDimension? dimension}) async {
    final session = _ref.read(kbSessionProvider);
    final WorldDimension targetDimension =
        dimension ?? _ref.read(selectedWorldDimensionProvider);
    if (session == null) {
      final world = World(
        id: newId(),
        title: 'World',
        dimension: targetDimension,
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
        final world = state!.world;
        if (dimension != null) {
          edit(world.copyWith(dimension: dimension));
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
        ).toJson(),
      );
      if (!mounted) return;
      await open(relativePath);
    }
  }

  @override
  void dispose() {
    _saveDebounce?.cancel();
    super.dispose();
  }
}
