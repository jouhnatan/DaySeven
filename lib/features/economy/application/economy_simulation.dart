/// Owns the running trade simulation: builds its network from the open World,
/// ticks it, and exposes play, pause, speed and reset.
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/economy/domain/trade_simulation.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/equirectangular_projection.dart';
import 'package:dayseven/shared/world/domain/world.dart';

class EconomySimulationController extends ChangeNotifier {
  TradeSimulation? _simulation;
  World? _world;
  String? _networkKey;
  Timer? _ticker;
  DateTime? _lastTick;
  double _speed = 1;

  /// The current run, or null before a World with a map is open.
  TradeSimulation? get simulation => _simulation;

  bool get isRunning => _ticker != null;
  double get speed => _speed;

  /// Rebuilds the run whenever the saved network stops matching the one the
  /// live run was built from. Cheap to call on every build.
  void configure(World? world) {
    final key = _networkKeyFor(world);
    if (world != null && key == _networkKey) return;
    _world = world;
    _networkKey = key;
    _rebuild();
  }

  void play() {
    if (_ticker != null || _simulation == null) return;
    _lastTick = DateTime.now();
    _ticker = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final now = DateTime.now();
      final last = _lastTick ?? now;
      _lastTick = now;
      final seconds = now.difference(last).inMicroseconds / 1e6;
      _simulation?.advance(seconds * _speed);
      notifyListeners();
    });
    notifyListeners();
  }

  void pause() {
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  void toggle() => isRunning ? pause() : play();

  void reset() {
    _rebuild();
    if (isRunning) {
      _lastTick = DateTime.now();
    }
  }

  void setSpeed(double speed) {
    _speed = speed.clamp(0.25, 4.0);
    notifyListeners();
  }

  void _rebuild() {
    final world = _world;
    _simulation = world == null ? null : _build(world);
    notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

TradeSimulation _build(World world) {
  final landmarks = <Model3DLandmark>[
    for (final landmark in world.model?.landmarks ?? const <Model3DLandmark>[])
      if (landmark.category == 'city') landmark,
  ];
  final byId = {for (final landmark in landmarks) landmark.id: landmark};
  final economy = world.economy;

  Offset pointOf(Model3DLandmark landmark) =>
      EquirectangularProjection.geographicToUv(
        latitude: landmark.latitude,
        longitude: landmark.longitude,
      );

  String? producedResource(String cityId) {
    final location = economy.locationForLandmark(cityId);
    final produced = location?.resourceIds ?? const [];
    if (produced.isNotEmpty) return produced.first;
    return economy.resourceTypes.isEmpty
        ? null
        : economy.resourceTypes.first.id;
  }

  int workersFor(String cityId) {
    final location = economy.locationForLandmark(cityId);
    final people = location == null
        ? 0
        : location.personCounts.values.fold<int>(0, (sum, n) => sum + n);
    final base = people > 0 ? people : (location?.population ?? 0) ~/ 100;
    return (1 + base ~/ 8).clamp(1, 5);
  }

  int tradersFor(String cityId) {
    final location = economy.locationForLandmark(cityId);
    return (1 + (location?.population ?? 0) ~/ 1500).clamp(1, 3);
  }

  final nodeRuns = <SimulationNodeRun>[];
  for (final node in economy.resourceNodes) {
    final home = node.homeLandmarkId;
    if (home == null) continue;
    final city = byId[home];
    if (city == null) continue;
    nodeRuns.add(
      SimulationNodeRun(
        id: node.id,
        cityId: home,
        city: pointOf(city),
        node: EquirectangularProjection.geographicToUv(
          latitude: node.latitude,
          longitude: node.longitude,
        ),
        resourceId: node.resourceId,
        workers: workersFor(home),
      ),
    );
  }

  final routeRuns = <SimulationRouteRun>[];
  for (final route in economy.tradeRoutes) {
    final from = byId[route.fromLandmarkId];
    final to = byId[route.toLandmarkId];
    if (from == null || to == null) continue;
    final resource =
        route.resourceId ?? producedResource(route.fromLandmarkId) ?? 'stone';
    final controls = [
      for (final control in route.controlPoints)
        if (control.length >= 2) Offset(control[0], control[1]),
    ];
    routeRuns.add(
      SimulationRouteRun(
        id: '${route.id}-forward',
        startCityId: route.fromLandmarkId,
        endCityId: route.toLandmarkId,
        from: pointOf(from),
        to: pointOf(to),
        controls: controls,
        resourceId: resource,
        traders: tradersFor(route.fromLandmarkId),
      ),
    );
    routeRuns.add(
      SimulationRouteRun(
        id: '${route.id}-back',
        startCityId: route.toLandmarkId,
        endCityId: route.fromLandmarkId,
        from: pointOf(to),
        to: pointOf(from),
        controls: controls.reversed.toList(),
        resourceId:
            route.resourceId ?? producedResource(route.toLandmarkId) ?? 'stone',
        traders: tradersFor(route.toLandmarkId),
      ),
    );
  }

  return TradeSimulation(nodeRuns: nodeRuns, routes: routeRuns);
}

String _networkKeyFor(World? world) {
  if (world == null) return 'none';
  final buffer = StringBuffer();
  for (final landmark in world.model?.landmarks ?? const <Model3DLandmark>[]) {
    if (landmark.category != 'city') continue;
    buffer
      ..write(landmark.id)
      ..write(landmark.latitude)
      ..write(landmark.longitude);
  }
  for (final route in world.economy.tradeRoutes) {
    buffer
      ..write(route.id)
      ..write(route.fromLandmarkId)
      ..write(route.toLandmarkId)
      ..write(route.resourceId)
      ..write(route.controlPoints);
  }
  for (final node in world.economy.resourceNodes) {
    buffer
      ..write(node.id)
      ..write(node.resourceId)
      ..write(node.latitude)
      ..write(node.longitude)
      ..write(node.homeLandmarkId);
  }
  return buffer.toString();
}

final economySimulationProvider =
    ChangeNotifierProvider<EconomySimulationController>(
      (ref) => EconomySimulationController(),
    );
