import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/features/world/ui/engines/orogen/orogen_settings_form.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('lists layers, toggles visibility, and removes a layer', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(openWorldProvider.notifier).state = const OpenWorld(
      relativePath: 'Aster.unearth',
      world: World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'orogen',
        layers: [
          WorldLayer(
            id: 'heightmap-1',
            kind: WorldLayerKind.heightmap,
            assetId: 'heightmap.png',
          ),
        ],
      ),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: OrogenSettingsForm()),
        ),
      ),
    );

    expect(find.text('Heightmap'), findsOneWidget);
    expect(
      find.byKey(const Key('world-layer-visibility-heightmap-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('world-layer-remove-heightmap-1')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const Key('world-layer-visibility-heightmap-1')),
    );
    await tester.pump();
    expect(
      container.read(openWorldProvider)!.world.layers.single.visible,
      isFalse,
    );

    await tester.tap(find.byKey(const Key('world-layer-remove-heightmap-1')));
    await tester.pump();
    expect(container.read(openWorldProvider)!.world.layers, isEmpty);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('shows the exact Orogen settings fields', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(openWorldProvider.notifier).state = const OpenWorld(
      relativePath: 'Aster.unearth',
      world: World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'orogen',
        engineSettings: {
          'orogen': {'planetCode': 'aster-1', 'activeLayerId': 'heightmap-1'},
        },
      ),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: OrogenSettingsForm()),
        ),
      ),
    );

    expect(find.text('Planet code'), findsOneWidget);
    expect(find.text('aster-1'), findsOneWidget);
    expect(find.text('Active layer'), findsOneWidget);
    expect(find.text('heightmap-1'), findsOneWidget);
    expect(find.text('Bump scale'), findsNothing);
    expect(find.text('Sea level'), findsNothing);
    expect(find.text('Sun lighting angle'), findsNothing);
  });
}
