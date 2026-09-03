import 'package:dayseven/features/world/application/world_engine_registry.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const registry = WorldEngineRegistry();

  test('three-dimensional Worlds offer Orogen', () {
    expect(registry.enginesFor(WorldDimension.threeD), [WorldEngine.orogen]);
    expect(registry.byId('orogen'), WorldEngine.orogen);
  });

  test('two-dimensional Worlds have no engine yet', () {
    expect(registry.enginesFor(WorldDimension.twoD), isEmpty);
    expect(registry.defaultFor(WorldDimension.twoD), isNull);
  });

  test('an unknown engine id is not resolved', () {
    expect(registry.byId('somefutureengine'), isNull);
  });

  test('the default is the first available engine', () {
    expect(registry.defaultFor(WorldDimension.threeD), WorldEngine.orogen);
  });
}
