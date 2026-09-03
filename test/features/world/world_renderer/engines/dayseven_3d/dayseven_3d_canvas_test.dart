import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/world_renderer/engines/dayseven_3d/dayseven_3d_canvas.dart';
import 'package:dayseven/shared/ui/theme.dart';

import '../../../../../support/kb_harness.dart';

void main() {
  late Directory temp;

  setUp(() async {
    final dirs = await createTempDirs('dayseven_canvas_test');
    temp = dirs.temp;
  });

  Future<ProviderContainer> pumpCanvas(
    WidgetTester tester, {
    DaySeven3DModel? model3d,
  }) async {
    final (container, kb) = await openTestKb(tester, temp);

    late String createdDocPath;
    await tester.runAsync(() async {
      createdDocPath = await kb.createDocument(
        title: 'Highpass',
        folderRelativePath: 'Lore',
      );
    });

    container.read(openWorldProvider.notifier).state = OpenWorld(
      relativePath: 'Aster.unearth',
      world: World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'dayseven_3d',
        model3d:
            model3d ??
            DaySeven3DModel(
              environment: const PlanetEnvironment(
                atmosphere: PlanetAtmosphere(enabled: true, density: 0.8),
              ),
              landmarks: [
                Model3DLandmark(
                  id: 'lm-1',
                  name: 'Highpass Citadel',
                  latitude: 10.0,
                  longitude: 0.0,
                  document: createdDocPath,
                ),
                Model3DLandmark(
                  id: 'lm-back',
                  name: 'Far Antimeridian',
                  latitude: 0.0,
                  longitude: 180.0,
                ),
              ],
            ),
      ),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(
            body: SizedBox(width: 800, height: 600, child: DaySeven3DCanvas()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('renders DaySeven 3D globe and landmark pin', (tester) async {
    await pumpCanvas(tester);

    expect(find.byKey(const Key('dayseven-3d-globe')), findsOneWidget);
    expect(find.text('Highpass Citadel'), findsOneWidget);
    expect(find.byKey(const ValueKey('pin-lm-1')), findsOneWidget);

    // Back-facing landmark is culled
    expect(find.text('Far Antimeridian'), findsNothing);
    expect(find.byKey(const ValueKey('pin-lm-back')), findsNothing);

    // Zoom and reset controls
    expect(find.byKey(const Key('dayseven-3d-zoom-in')), findsOneWidget);
    expect(find.byKey(const Key('dayseven-3d-zoom-out')), findsOneWidget);
    expect(find.byKey(const Key('dayseven-3d-reset-view')), findsOneWidget);

    await tester.tap(find.byKey(const Key('dayseven-3d-zoom-in')));
    await tester.pumpAndSettle();

    // Reset view becomes active after zoom
    final resetBtn = find.byKey(const Key('dayseven-3d-reset-view'));
    expect(resetBtn, findsOneWidget);
    await tester.tap(resetBtn);
    await tester.pumpAndSettle();
  });

  testWidgets(
    'drag gesture rotates the globe and updates landmark projection',
    (tester) async {
      await pumpCanvas(tester);

      final initialPinFinder = find.byKey(const ValueKey('pin-lm-1'));
      expect(initialPinFinder, findsOneWidget);
      final initialPos = tester.getCenter(initialPinFinder);

      // Drag globe slightly horizontally to yaw
      await tester.drag(
        find.byKey(const Key('dayseven-3d-globe')),
        const Offset(60, 0),
      );
      await tester.pumpAndSettle();

      final rotatedPinFinder = find.byKey(const ValueKey('pin-lm-1'));
      expect(rotatedPinFinder, findsOneWidget);
      final newPos = tester.getCenter(rotatedPinFinder);
      expect(newPos.dx, isNot(equals(initialPos.dx)));
    },
  );

  testWidgets('clicking landmark pin opens linked document', (tester) async {
    final container = await pumpCanvas(tester);

    await tester.runAsync(() async {
      await tester.tap(find.text('Highpass Citadel'));
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (container.read(documentControllerProvider)?.relativePath !=
              'Lore/Highpass.md' &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
    });
    await tester.pumpAndSettle();

    // Verify view switched to editor and document is loaded
    expect(container.read(viewProvider), DsView.editor);
    expect(
      container.read(documentControllerProvider)?.relativePath,
      'Lore/Highpass.md',
    );
  });
}
