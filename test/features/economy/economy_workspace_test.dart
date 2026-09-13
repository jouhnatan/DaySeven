/// The Economy view: placement, editing, routes, handles and playback.
library;

import 'dart:io';

import 'package:dayseven/app/view.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/world_providers.dart';
import 'package:dayseven/features/economy/application/economy_providers.dart';
import 'package:dayseven/features/economy/application/economy_simulation.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/economy.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/kb_harness.dart';
import '../../support/test_fonts.dart';
import '../../support/widget_harness.dart';

void main() {
  late Directory temp;

  setUp(() async {
    await loadTestFonts();
    final dirs = await createTempDirs('dayseven_economy_test');
    temp = dirs.temp;
  });

  Future<ProviderContainer> economyView(
    WidgetTester tester, {
    required World world,
    bool withMapAsset = true,
  }) async {
    final container = await seededKbContainer(tester, temp);
    final kb = container.read(kbSessionProvider)!.kb;

    await tester.runAsync(() async {
      if (withMapAsset) {
        final asset = File(kb.assetPathFor('map.png'));
        await asset.parent.create(recursive: true);
        await asset.writeAsBytes(_png(width: 400, height: 200));
      }
      final path = await kb.createObject(name: 'MyWorld', seed: world.toJson());
      await container.read(openWorldProvider.notifier).open(path);
    });

    container.read(viewProvider.notifier).state = DsView.economy;
    await pumpDsShell(tester, container);
    return container;
  }

  Future<void> settleSaves(WidgetTester tester, ProviderContainer container) async {
    await tester.pump(const Duration(milliseconds: 700));
    await tester.runAsync(
      () => container.read(openWorldProvider.notifier).flush(),
    );
  }

  testWidgets('the map replaces the left side and the stats pane sits right', (
    tester,
  ) async {
    await economyView(tester, world: World(id: 'w1', title: 'MyWorld'));

    expect(find.byKey(const Key('centre-workspace')), findsOneWidget);
    expect(find.byKey(const Key('economy-map-canvas')), findsOneWidget);
    expect(find.byKey(const Key('economy-stats-pane')), findsOneWidget);
    expect(find.byKey(const Key('knowledge-base-pane')), findsNothing);
    expect(find.byKey(const Key('world-settings-pane')), findsNothing);
    expect(find.byKey(const Key('timeline-editor-pane')), findsNothing);
  });

  testWidgets('without a map the centre asks for one, shared with World', (
    tester,
  ) async {
    await economyView(tester, world: World(id: 'w1', title: 'MyWorld'));

    expect(find.text('Add a source map'), findsOneWidget);
    expect(find.byKey(const Key('economy-add-map-button')), findsOneWidget);
  });

  testWidgets('the tabs switch between Locations, Resources and Simulate', (
    tester,
  ) async {
    await economyView(
      tester,
      world: _world(economy: WorldEconomy.seeded()),
    );

    expect(
      find.byKey(const Key('economy-empty-add-location')),
      findsOneWidget,
    );

    await _showTab(tester, 'Resources');
    expect(find.byKey(const Key('economy-add-resource')), findsOneWidget);
    expect(find.byKey(const Key('economy-add-person-type-section')), findsOneWidget);

    await _showTab(tester, 'Simulate');
    expect(find.byKey(const Key('economy-simulate-play')), findsOneWidget);
    expect(find.byKey(const Key('economy-add-route')), findsOneWidget);
  });

  testWidgets('a city opens into its stats and the caret goes back', (
    tester,
  ) async {
    final economy = WorldEconomy.seeded().withLocation(
      EconomyLocation(id: 'e1', landmarkId: 'c1', population: 1200),
    );
    await economyView(
      tester,
      world: _world(
        economy: economy,
        cities: [
          Model3DLandmark(
            id: 'c1',
            name: 'Aldenmoor',
            latitude: 0,
            longitude: 0,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('economy-city-row-c1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('economy-population-row')), findsOneWidget);
    expect(find.text('1,200'), findsOneWidget);
    expect(find.byKey(const Key('economy-population-slider')), findsOneWidget);

    await tester.tap(find.byKey(const Key('economy-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('economy-city-row-c1')), findsOneWidget);
  });

  testWidgets('the population slider writes to the shared World object', (
    tester,
  ) async {
    final economy = WorldEconomy.seeded().withLocation(
      EconomyLocation(id: 'e1', landmarkId: 'c1', population: 1000),
    );
    final container = await economyView(
      tester,
      world: _world(
        economy: economy,
        cities: [
          Model3DLandmark(
            id: 'c1',
            name: 'Aldenmoor',
            latitude: 0,
            longitude: 0,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('economy-city-row-c1')));
    await tester.pumpAndSettle();
    await tester.drag(
      find.byKey(const Key('economy-population-slider')),
      const Offset(40, 0),
    );
    await tester.pump();

    final population = container
        .read(openWorldProvider)!
        .world
        .economy
        .locationForLandmark('c1')!
        .population;
    expect(population, greaterThan(1000));
    await settleSaves(tester, container);
  });

  testWidgets('a person type is added from the city and shows in Resources', (
    tester,
  ) async {
    final economy = WorldEconomy.seeded()
        .withLocation(
          EconomyLocation(id: 'e1', landmarkId: 'c1', population: 400),
        )
        .withPersonType(const PersonType(id: 'p1', name: 'Farmers'));
    final container = await economyView(
      tester,
      world: _world(
        economy: economy,
        cities: [
          Model3DLandmark(
            id: 'c1',
            name: 'Aldenmoor',
            latitude: 0,
            longitude: 0,
          ),
        ],
      ),
    );

    await tester.tap(find.byKey(const ValueKey('economy-city-row-c1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('economy-add-person-type')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.descendant(
        of: find.byType(DsDialog),
        matching: find.byType(TextField),
      ),
      'Bakers',
    );
    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();

    final types = container.read(openWorldProvider)!.world.economy.personTypes;
    expect(types.map((type) => type.name), contains('Bakers'));

    await _showTab(tester, 'Resources');
    expect(find.text('Bakers'), findsOneWidget);
    await settleSaves(tester, container);
  });

  testWidgets('two city taps draw a trade route with draggable handles', (
    tester,
  ) async {
    final container = await economyView(
      tester,
      world: _world(
        cities: [
          Model3DLandmark(
            id: 'c1',
            name: 'Aldenmoor',
            latitude: 0,
            longitude: -20,
          ),
          Model3DLandmark(
            id: 'c2',
            name: 'Oakhaven',
            latitude: 0,
            longitude: 20,
          ),
        ],
      ),
    );

    container.read(economyToolProvider.notifier).state = EconomyTool.addRoute;
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('economy-city-c1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('economy-city-c2')));
    await tester.pumpAndSettle();

    final route = container.read(openWorldProvider)!.world.economy.tradeRoutes.single;
    expect(route.fromLandmarkId, 'c1');
    expect(route.toLandmarkId, 'c2');
    expect(route.controlPoints, hasLength(2));

    final handle = find.byKey(
      ValueKey('economy-route-handle-${route.id}-0'),
    );
    expect(handle, findsOneWidget);

    final before = route.controlPoints.first;
    await tester.drag(handle, const Offset(20, 20));
    await tester.pumpAndSettle();

    final after = container
        .read(openWorldProvider)!
        .world
        .economy
        .tradeRoutes
        .single
        .controlPoints
        .first;
    expect(after, isNot(equals(before)));
    await settleSaves(tester, container);
  });

  testWidgets('a resource node joins the Locations list and can be placed', (
    tester,
  ) async {
    final container = await economyView(tester, world: _world());

    container.read(economyToolProvider.notifier).state = EconomyTool.addNode;
    container.read(economyNodeResourceProvider.notifier).state = 'gold';
    await tester.pump();

    await tester.tapAt(const Offset(400, 300));
    await tester.pumpAndSettle();

    final nodes = container.read(openWorldProvider)!.world.economy.resourceNodes;
    expect(nodes, hasLength(1));
    expect(nodes.single.resourceId, 'gold');
    container.read(selectedEconomyLocationProvider.notifier).state = null;
    await tester.pumpAndSettle();
    expect(
      find.byKey(ValueKey('economy-node-row-${nodes.single.id}')),
      findsOneWidget,
    );
    await settleSaves(tester, container);
  });

  testWidgets('the simulation plays, reports stockpiles and resets', (
    tester,
  ) async {
    final economy = WorldEconomy.seeded()
        .withLocation(EconomyLocation(id: 'e1', landmarkId: 'c1'))
        .withLocation(EconomyLocation(id: 'e2', landmarkId: 'c2'))
        .withTradeRoute(
          TradeRoute(
            id: 'r1',
            fromLandmarkId: 'c1',
            toLandmarkId: 'c2',
            resourceId: 'gold',
            controlPoints: [
              [0.4, 0.4],
              [0.6, 0.4],
            ],
          ),
        );
    final container = await economyView(
      tester,
      world: _world(
        economy: economy,
        cities: [
          Model3DLandmark(
            id: 'c1',
            name: 'Aldenmoor',
            latitude: 0,
            longitude: -20,
          ),
          Model3DLandmark(
            id: 'c2',
            name: 'Oakhaven',
            latitude: 0,
            longitude: 20,
          ),
        ],
      ),
    );

    await _showTab(tester, 'Simulate');
    expect(find.text('Aldenmoor to Oakhaven'), findsOneWidget);

    final simulation = container.read(economySimulationProvider);
    await tester.tap(find.byKey(const Key('economy-simulate-play')));
    await tester.pump(const Duration(milliseconds: 100));
    expect(simulation.isRunning, isTrue);

    await tester.tap(find.byKey(const Key('economy-simulate-play')));
    await tester.pump();
    expect(simulation.isRunning, isFalse);

    await tester.tap(find.byKey(const Key('economy-simulate-reset')));
    await tester.pump();
    expect(simulation.simulation, isNotNull);
  });
}

World _world({
  WorldEconomy? economy,
  List<Model3DLandmark> cities = const [],
}) => World(
  id: 'w1',
  title: 'MyWorld',
  model: DaySeven3DModel(
    sourceMapLayerId: 'surface',
    layers: const [
      Model3DLayer(
        id: 'surface',
        name: 'Surface',
        type: Model3DLayerType.albedo,
        assetId: 'map.png',
        visible: true,
      ),
    ],
    landmarks: cities,
  ),
  economy: economy ?? WorldEconomy.seeded(),
);

Future<void> _showTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byKey(const Key('economy-tabs')),
      matching: find.text(label),
    ),
  );
  await tester.pumpAndSettle();
}

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

List<int> _png({required int width, required int height}) => [
  ..._pngSignature,
  ..._chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 6, 0, 0, 0]),
  ..._chunk('IEND', const []),
];

List<int> _chunk(String type, List<int> data) => [
  ..._uint32(data.length),
  ...type.codeUnits,
  ...data,
  ..._uint32(0),
];

List<int> _uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];
