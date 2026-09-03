import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/features/world/world_renderer/engines/orogen/orogen_canvas.dart';
import 'package:dayseven/features/world/world_renderer/globe_painter.dart';
import 'package:dayseven/features/world/world_renderer/globe_viewport.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('drag rotates the globe and controls zoom and reset', (
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
            id: 'satellite-1',
            kind: WorldLayerKind.satellite,
            assetId: 'satellite.png',
          ),
        ],
      ),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: dsTheme(), home: const OrogenCanvas()),
      ),
    );
    await tester.pump();

    GlobePainter painter() =>
        tester
                .widget<CustomPaint>(find.byKey(const Key('orogen-globe')))
                .painter!
            as GlobePainter;

    final viewport = painter().viewport;
    await tester.dragFrom(const Offset(30, 30), const Offset(80, 20));
    await tester.pump();
    expect(viewport.yaw, isNot(0));
    expect(viewport.pitch, isNot(0));

    await tester.tap(find.byKey(const Key('world-zoom-in')));
    await tester.pump();
    expect(viewport.scale, greaterThan(kGlobeMinScale));

    await tester.tap(find.byKey(const Key('world-reset')));
    await tester.pump();
    expect(viewport.pitch, 0);
    expect(viewport.yaw, 0);
    expect(viewport.scale, kGlobeMinScale);
  });
}
