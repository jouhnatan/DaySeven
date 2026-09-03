import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world.dart';
import 'package:dayseven/features/world/ui/engines/dayseven_3d/dayseven_3d_settings_form.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

void main() {
  Future<ProviderContainer> pumpForm(
    WidgetTester tester, {
    DaySeven3DModel? model3d,
  }) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(openWorldProvider.notifier).state = OpenWorld(
      relativePath: 'Aster.unearth',
      world: World(
        id: 'world-1',
        title: 'Aster',
        engineId: 'dayseven_3d',
        model3d: model3d ?? DaySeven3DModel(),
      ),
      dirty: false,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: DaySeven3DSettingsForm()),
          ),
        ),
      ),
    );
    return container;
  }

  testWidgets('renders sections and toggles atmosphere and ocean', (
    tester,
  ) async {
    final container = await pumpForm(tester);

    expect(find.text('3D Model & Environment'), findsOneWidget);
    expect(find.text('Texture Layers'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Planetary Geometry'), findsOneWidget);
    expect(find.text('Landmarks (0)'), findsOneWidget);
    expect(find.text('Export 3D World'), findsOneWidget);
    expect(find.byKey(const Key('export-model-json-button')), findsOneWidget);
    expect(find.byKey(const Key('export-geojson-button')), findsOneWidget);
    expect(find.byKey(const Key('export-threejs-html-button')), findsOneWidget);

    // Toggle atmosphere
    final atmosphereSwitch = find.descendant(
      of: find.byKey(const Key('dayseven-3d-atmosphere-setting')),
      matching: find.byType(Switch),
    );
    await tester.tap(atmosphereSwitch);
    await tester.pump();

    expect(
      container
          .read(openWorldProvider)!
          .world
          .model3d!
          .environment
          .atmosphere
          .enabled,
      isFalse,
    );

    // Toggle ocean
    final oceanSwitch = find.descendant(
      of: find.byKey(const Key('dayseven-3d-ocean-setting')),
      matching: find.byType(Switch),
    );
    await tester.tap(oceanSwitch);
    await tester.pump();

    expect(
      container
          .read(openWorldProvider)!
          .world
          .model3d!
          .environment
          .ocean
          .enabled,
      isFalse,
    );

    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('validates inputs and adds a landmark through the dialog', (
    tester,
  ) async {
    final container = await pumpForm(tester);

    final addBtn = find.byKey(const Key('dayseven-3d-add-landmark-button'));
    await tester.ensureVisible(addBtn);
    await tester.pumpAndSettle();

    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    expect(find.text('Add Landmark Pin'), findsOneWidget);

    // Attempt save with empty name
    await tester.tap(find.byKey(const Key('landmark-dialog-save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);

    // Attempt save with invalid latitude
    await tester.enterText(
      find.byKey(const Key('landmark-name-input')),
      'Citadel of Sol',
    );
    await tester.enterText(find.byKey(const Key('landmark-lat-input')), '95.0');
    await tester.tap(find.byKey(const Key('landmark-dialog-save-button')));
    await tester.pumpAndSettle();
    expect(find.text('Latitude must be between -90 and 90'), findsOneWidget);

    // Enter valid coordinates
    await tester.enterText(find.byKey(const Key('landmark-lat-input')), '15.5');
    await tester.enterText(
      find.byKey(const Key('landmark-lon-input')),
      '-42.0',
    );
    await tester.enterText(
      find.byKey(const Key('landmark-doc-input')),
      'Lore/Citadel.md',
    );

    await tester.tap(find.byKey(const Key('landmark-dialog-save-button')));
    await tester.pumpAndSettle();

    final landmarks = container
        .read(openWorldProvider)!
        .world
        .model3d!
        .landmarks;
    expect(landmarks.length, 1);
    expect(landmarks.first.name, 'Citadel of Sol');
    expect(landmarks.first.latitude, 15.5);
    expect(landmarks.first.longitude, -42.0);
    expect(landmarks.first.document, 'Lore/Citadel.md');
    expect(find.text('Citadel of Sol'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets(
    'renders texture layers, toggles visibility, and confirms removal',
    (tester) async {
      final container = await pumpForm(
        tester,
        model3d: DaySeven3DModel(
          layers: [
            const Model3DLayer(
              id: 'l-1',
              name: 'Primary Heightmap',
              type: Model3DLayerType.heightmap,
              assetId: 'heightmap.png',
              visible: true,
            ),
          ],
        ),
      );

      expect(find.text('Primary Heightmap'), findsOneWidget);
      expect(find.text('Elevation (Heightmap)'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide layer'));
      await tester.pump();

      final layers = container.read(openWorldProvider)!.world.model3d!.layers;
      expect(layers.first.visible, isFalse);

      // Tap remove -> confirmation dialog
      await tester.tap(find.byTooltip('Remove layer'));
      await tester.pumpAndSettle();

      expect(find.text('Remove “Primary Heightmap”?'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();

      expect(container.read(openWorldProvider)!.world.model3d!.layers, isEmpty);
      await tester.pump(const Duration(milliseconds: 700));
    },
  );

  testWidgets('confirms landmark deletion', (tester) async {
    final container = await pumpForm(
      tester,
      model3d: DaySeven3DModel(
        landmarks: [
          Model3DLandmark(
            id: 'lm-1',
            name: 'Ancient Spire',
            latitude: 10.0,
            longitude: 20.0,
          ),
        ],
      ),
    );

    final landmarkFinder = find.text('Ancient Spire');
    await tester.ensureVisible(landmarkFinder);
    await tester.pumpAndSettle();

    expect(landmarkFinder, findsOneWidget);

    final deleteBtn = find.byTooltip('Delete landmark');
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    expect(find.text('Delete “Ancient Spire”?'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(
      container.read(openWorldProvider)!.world.model3d!.landmarks,
      isEmpty,
    );
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets(
    'export buttons expose accessible semantic labels and are interactive',
    (tester) async {
      await pumpForm(tester);

      final jsonBtn = find.byKey(const Key('export-model-json-button'));
      final geoJsonBtn = find.byKey(const Key('export-geojson-button'));
      final htmlBtn = find.byKey(const Key('export-threejs-html-button'));

      await tester.ensureVisible(jsonBtn);
      await tester.pumpAndSettle();

      expect(jsonBtn, findsOneWidget);
      expect(geoJsonBtn, findsOneWidget);
      expect(htmlBtn, findsOneWidget);

      expect(
        tester.widget<DsButton>(jsonBtn).semanticLabel,
        'Export model metadata as JSON',
      );
      expect(
        tester.widget<DsButton>(geoJsonBtn).semanticLabel,
        'Export landmarks and regions as GeoJSON',
      );
      expect(
        tester.widget<DsButton>(htmlBtn).semanticLabel,
        'Export standalone WebGL 3D Viewer HTML',
      );
      await tester.pump(const Duration(milliseconds: 700));
    },
  );
}
