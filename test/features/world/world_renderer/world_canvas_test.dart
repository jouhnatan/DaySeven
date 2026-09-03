import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/world_renderer/engines/orogen/orogen_canvas.dart';
import 'package:dayseven/features/world/world_renderer/world_canvas.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the honest empty state for two dimensions', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(selectedWorldDimensionProvider.notifier).state =
        WorldDimension.twoD;

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: dsTheme(), home: const WorldCanvas()),
      ),
    );

    expect(find.text('No 2D engine available yet.'), findsOneWidget);
    expect(find.byType(OrogenCanvas), findsNothing);
  });

  testWidgets('dispatches an active Orogen world to its canvas', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(openWorldProvider.notifier).state = const OpenWorld(
      relativePath: 'Aster.unearth',
      world: World(id: 'world-1', title: 'Aster', engineId: 'orogen'),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: dsTheme(), home: const WorldCanvas()),
      ),
    );
    await tester.pump();

    expect(find.byType(OrogenCanvas), findsOneWidget);
    expect(find.byKey(const Key('orogen-globe')), findsOneWidget);
  });

  testWidgets('dispatches an active DaySeven 3D world to its canvas', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(openWorldProvider.notifier).state = OpenWorld(
      relativePath: 'Aster.unearth',
      world: const World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'dayseven_3d',
      ),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: dsTheme(), home: const WorldCanvas()),
      ),
    );
    await tester.pump();

    expect(find.byKey(const Key('dayseven-3d-globe')), findsOneWidget);
  });
}
