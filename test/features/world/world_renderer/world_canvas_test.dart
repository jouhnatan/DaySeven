import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/world_renderer/engines/dayseven_2d/dayseven_2d_canvas.dart';
import 'package:dayseven/features/world/world_renderer/engines/dayseven_3d/dayseven_3d_canvas.dart';
import 'package:dayseven/features/world/world_renderer/world_canvas.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(WidgetTester tester, WorldDimension dimension) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(selectedWorldDimensionProvider.notifier).state = dimension;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: dsTheme(), home: const WorldCanvas()),
      ),
    );
    await tester.pump();
  }

  testWidgets('dispatches 2D to the flat map renderer', (tester) async {
    await pump(tester, WorldDimension.twoD);
    expect(find.byType(DaySeven2DCanvas), findsOneWidget);
    expect(find.byType(DaySeven3DCanvas), findsNothing);
  });

  testWidgets('dispatches 3D to the globe renderer', (tester) async {
    await pump(tester, WorldDimension.threeD);
    expect(find.byType(DaySeven3DCanvas), findsOneWidget);
    expect(find.byType(DaySeven2DCanvas), findsNothing);
  });
}
