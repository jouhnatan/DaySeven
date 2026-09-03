import 'dart:io';

import 'package:flutter/gestures.dart';
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
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets(
    'drop-pin toggle enables mode, displays banner, and can be cancelled',
    (tester) async {
      final container = await pumpCanvas(tester);

      expect(container.read(dropPinModeProvider), isFalse);
      expect(find.byKey(const Key('dayseven-3d-drop-pin-banner')), findsNothing);

      // Tap toggle button
      final toggleBtn = find.byKey(const Key('dayseven-3d-drop-pin-toggle'));
      expect(toggleBtn, findsOneWidget);
      await tester.tap(toggleBtn);
      await tester.pumpAndSettle();

      expect(container.read(dropPinModeProvider), isTrue);
      expect(
        find.byKey(const Key('dayseven-3d-drop-pin-banner')),
        findsOneWidget,
      );
      expect(
        find.text('Click anywhere on the globe to drop a landmark pin'),
        findsOneWidget,
      );

      // Cancel drop pin mode
      await tester.tap(find.byKey(const Key('dayseven-3d-cancel-drop-pin')));
      await tester.pumpAndSettle();

      expect(container.read(dropPinModeProvider), isFalse);
      expect(find.byKey(const Key('dayseven-3d-drop-pin-banner')), findsNothing);
    },
  );

  testWidgets(
    'dropping pin on the globe via tap in drop-pin mode opens dialog prefilled with coordinates and adds landmark',
    (tester) async {
      final container = await pumpCanvas(tester);

      // Enable drop pin mode
      await tester.tap(find.byKey(const Key('dayseven-3d-drop-pin-toggle')));
      await tester.pumpAndSettle();

      // Tap the center of the globe (viewport center is 400, 300 for 800x600 size)
      await tester.tapAt(const Offset(400, 300));
      await tester.pumpAndSettle();

      // Dialog should be open
      expect(find.text('Add Landmark Pin'), findsOneWidget);

      // Coordinates at center should be pre-filled to approximately 0.00, 0.00
      final latInput = tester.widget<TextField>(
        find.byKey(const Key('landmark-lat-input')),
      );
      final lonInput = tester.widget<TextField>(
        find.byKey(const Key('landmark-lon-input')),
      );
      expect(double.parse(latInput.controller!.text), closeTo(0.0, 0.1));
      expect(double.parse(lonInput.controller!.text), closeTo(0.0, 0.1));

      // Enter name and save
      await tester.enterText(
        find.byKey(const Key('landmark-name-input')),
        'Equatorial Outpost',
      );
      await tester.tap(find.byKey(const Key('landmark-dialog-save-button')));
      await tester.pumpAndSettle();

      // Verify landmark was added to the model and renders on globe
      final landmarks =
          container.read(openWorldProvider)!.world.model3d!.landmarks;
      expect(
        landmarks.any((lm) => lm.name == 'Equatorial Outpost'),
        isTrue,
      );
      expect(find.text('Equatorial Outpost'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets(
    'dropping pin on the globe via secondary tap opens dialog directly',
    (tester) async {
      await pumpCanvas(tester);

      // Secondary tap (right-click) at center without activating toggle
      final globeFinder = find.byKey(const Key('dayseven-3d-globe'));
      final globeCenter = tester.getCenter(globeFinder);

      final gesture = await tester.startGesture(
        globeCenter,
        kind: PointerDeviceKind.mouse,
        buttons: kSecondaryMouseButton,
      );
      await gesture.up();
      await tester.pumpAndSettle();

      // Dialog opens directly
      expect(find.text('Add Landmark Pin'), findsOneWidget);

      // Cancel dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Add Landmark Pin'), findsNothing);
    },
  );

  testWidgets(
    'tap outside globe sphere disc does not trigger drop-pin dialog',
    (tester) async {
      await pumpCanvas(tester);

      // Enable drop pin mode
      await tester.tap(find.byKey(const Key('dayseven-3d-drop-pin-toggle')));
      await tester.pumpAndSettle();

      // Tap corner (0, 0), which is outside the sphere disc
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Dialog should NOT open
      expect(find.text('Add Landmark Pin'), findsNothing);
      expect(
        find.byKey(const Key('dayseven-3d-drop-pin-banner')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'tapping landmark without document opens edit dialog and allows updating',
    (tester) async {
      final container = await pumpCanvas(tester);

      // Add a landmark with no linked document
      final controller = container.read(openWorldProvider.notifier);
      controller.addLandmark(
        Model3DLandmark(
          id: 'lm-no-doc',
          name: 'Silent Monolith',
          latitude: 5.0,
          longitude: 5.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Silent Monolith'), findsOneWidget);

      // Tap the landmark pin
      await tester.tap(find.text('Silent Monolith'));
      await tester.pumpAndSettle();

      // Edit dialog should open
      expect(find.text('Edit Landmark Pin'), findsOneWidget);

      // Update name
      await tester.enterText(
        find.byKey(const Key('landmark-name-input')),
        'Awakened Monolith',
      );
      await tester.tap(find.byKey(const Key('landmark-dialog-save-button')));
      await tester.pumpAndSettle();

      expect(find.text('Awakened Monolith'), findsOneWidget);
      final updated = container
          .read(openWorldProvider)!
          .world
          .model3d!
          .landmarks
          .firstWhere((lm) => lm.id == 'lm-no-doc');
      expect(updated.name, 'Awakened Monolith');
      await tester.pump(const Duration(milliseconds: 500));
    },
  );

  testWidgets('edit dialog allows deleting landmark pin', (tester) async {
    final container = await pumpCanvas(tester);

    final controller = container.read(openWorldProvider.notifier);
    controller.addLandmark(
      Model3DLandmark(
        id: 'lm-to-delete',
        name: 'Vanishing Tower',
        latitude: -10.0,
        longitude: -10.0,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vanishing Tower'), findsOneWidget);

    // Tap to open edit dialog
    await tester.tap(find.text('Vanishing Tower'));
    await tester.pumpAndSettle();

    expect(find.text('Edit Landmark Pin'), findsOneWidget);

    // Tap Delete button
    await tester.tap(find.byKey(const Key('landmark-dialog-delete-button')));
    await tester.pumpAndSettle();

    expect(find.text('Vanishing Tower'), findsNothing);
    final landmarks =
        container.read(openWorldProvider)!.world.model3d!.landmarks;
    expect(landmarks.any((lm) => lm.id == 'lm-to-delete'), isFalse);
    await tester.pump(const Duration(milliseconds: 500));
  });
}
