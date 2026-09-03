import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/ui/world_settings_pane.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpPane(
    WidgetTester tester, {
    World world = const World(
      id: 'world-1',
      title: 'Aster',
      engineId: 'orogen',
    ),
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(openWorldProvider.notifier).state = OpenWorld(
      relativePath: 'Aster.unearth',
      world: world,
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
    return container;
  }

  testWidgets('switches between dimensions and shows the 2D status', (
    tester,
  ) async {
    final container = await pumpPane(tester);

    await tester.tap(find.text('2D'));
    await tester.pump();

    expect(container.read(selectedWorldDimensionProvider), WorldDimension.twoD);
    expect(
      container.read(openWorldProvider)!.world.dimension,
      WorldDimension.twoD,
    );
    expect(container.read(openWorldProvider)!.world.engineId, isNull);
    expect(find.byType(DsStatusBlock), findsOneWidget);
    expect(find.text('No 2D engines available'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('chooses the available World Orogen engine', (tester) async {
    final container = await pumpPane(
      tester,
      world: const World(id: 'world-1', title: 'Aster'),
    );

    final buttonRect = tester.getRect(
      find.byKey(const Key('world-engine-dropdown')),
    );

    await tester.tap(find.byKey(const Key('world-engine-dropdown')));
    await tester.pumpAndSettle();

    final popupCard = tester.getRect(
      find.byWidgetPredicate((w) => w is Material && w.elevation == 4),
    );

    // Dropdown opens directly beneath the anchor, not at the window top-left.
    expect(popupCard.top, buttonRect.bottom);
    expect(popupCard.right, buttonRect.right);
    expect(find.text('World Orogen'), findsOneWidget);

    await tester.tap(find.text('World Orogen'));
    await tester.pumpAndSettle();

    expect(container.read(openWorldProvider)!.world.engineId, 'orogen');
    expect(find.text('World Orogen'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('shows the Orogen form only for the active 3D engine', (
    tester,
  ) async {
    await pumpPane(tester);

    expect(find.text('Layers'), findsOneWidget);
    expect(find.text('Planet code'), findsOneWidget);

    await tester.tap(find.text('2D'));
    await tester.pump();
    expect(find.text('Layers'), findsNothing);
    await tester.pump(const Duration(milliseconds: 700));
  });
}
