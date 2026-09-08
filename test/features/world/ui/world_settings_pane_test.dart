import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/ui/world_settings_pane.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('offers only 3D and 2D render modes', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(openWorldProvider.notifier).state = const OpenWorld(
      relativePath: 'Aster.unearth',
      world: World(id: 'world-1', title: 'Aster'),
      dirty: false,
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: WorldSettingsPane()),
        ),
      ),
    );

    expect(find.text('Render as'), findsOneWidget);
    expect(find.text('Engine'), findsNothing);
    await tester.tap(find.byKey(const Key('world-render-mode-dropdown')));
    await tester.pumpAndSettle();
    expect(find.text('2D'), findsOneWidget);
    expect(find.text('World Orogen'), findsNothing);

    await tester.tap(find.text('2D'));
    await tester.pump();
    expect(container.read(selectedWorldDimensionProvider), WorldDimension.twoD);
    expect(
      container.read(openWorldProvider)!.world.dimension,
      WorldDimension.twoD,
    );
    await tester.pump(const Duration(milliseconds: 700));
  });
}
