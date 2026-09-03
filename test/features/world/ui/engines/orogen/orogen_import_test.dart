import 'dart:async';
import 'dart:io';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/data/world_asset_repository.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/features/world/ui/engines/orogen/orogen_settings_form.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../../../support/kb_harness.dart';

class FakeFileSelector extends FileSelectorPlatform {
  FakeFileSelector({this.file, this.error});

  final XFile? file;
  final Object? error;
  List<XTypeGroup>? acceptedTypeGroups;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    this.acceptedTypeGroups = acceptedTypeGroups;
    if (error case final error?) throw error;
    return file;
  }
}

class BlockingWorldAssetRepository extends WorldAssetRepository {
  BlockingWorldAssetRepository(super.kb);

  final result = Completer<WorldLayer>();

  @override
  Future<WorldLayer> importLayer({
    required String id,
    required WorldLayerKind kind,
    required File source,
  }) => result.future;
}

class RecordingWorldAssetRepository extends WorldAssetRepository {
  RecordingWorldAssetRepository(super.kb, this.layer);

  final WorldLayer layer;
  File? importedSource;

  @override
  Future<WorldLayer> importLayer({
    required String id,
    required WorldLayerKind kind,
    required File source,
  }) {
    importedSource = source;
    return Future<WorldLayer>.value(layer);
  }
}

class ThrowingWorldAssetRepository extends WorldAssetRepository {
  ThrowingWorldAssetRepository(super.kb, this.error);

  final Object error;

  @override
  Future<WorldLayer> importLayer({
    required String id,
    required WorldLayerKind kind,
    required File source,
  }) => Future<WorldLayer>.error(error);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late FileSelectorPlatform originalFileSelector;

  setUp(() async {
    final dirs = await createTempDirs('orogen_import_test');
    temp = dirs.temp;
    originalFileSelector = FileSelectorPlatform.instance;
    addTearDown(() => FileSelectorPlatform.instance = originalFileSelector);
  });

  testWidgets('imports a PNG layer through OrogenSettingsForm', (tester) async {
    late RecordingWorldAssetRepository repository;
    final (container, _) = await openTestKb(
      tester,
      temp,
      name: 'Awayside',
      overrides: [
        worldAssetRepositoryProvider.overrideWith((ref) {
          repository = RecordingWorldAssetRepository(
            ref.watch(kbSessionProvider)!.kb,
            const WorldLayer(
              id: 'layer-1',
              kind: WorldLayerKind.heightmap,
              assetId: 'heightmap.png',
            ),
          );
          return repository;
        }),
      ],
    );
    final controller = container.read(openWorldProvider.notifier);
    await tester.runAsync(() => controller.setEngine('orogen'));

    final samplePng = File(p.join(temp.path, 'equirectangular.png'));
    await tester.runAsync(
      () => samplePng.writeAsBytes(_png(width: 4, height: 2)),
    );

    final selector = FakeFileSelector(file: XFile(samplePng.path));
    FileSelectorPlatform.instance = selector;

    await _pumpForm(tester, container);

    expect(find.byKey(const Key('world-import-layer')), findsOneWidget);
    await tester.tap(find.byKey(const Key('world-import-layer')));
    await tester.pump();
    await tester.pump();

    final typeGroup = selector.acceptedTypeGroups!.single;
    expect(typeGroup.extensions, ['png']);
    expect(typeGroup.uniformTypeIdentifiers, ['public.png']);

    final layer = container.read(openWorldProvider)!.world.layers.single;
    expect(layer.kind, WorldLayerKind.heightmap);
    expect(layer.assetId, 'heightmap.png');
    expect(repository.importedSource!.path, samplePng.path);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('shows progress and disables import while it is running', (
    tester,
  ) async {
    late BlockingWorldAssetRepository repository;
    final (container, _) = await openTestKb(
      tester,
      temp,
      name: 'Awayside',
      overrides: [
        worldAssetRepositoryProvider.overrideWith((ref) {
          repository = BlockingWorldAssetRepository(
            ref.watch(kbSessionProvider)!.kb,
          );
          return repository;
        }),
      ],
    );
    final controller = container.read(openWorldProvider.notifier);
    await tester.runAsync(() => controller.setEngine('orogen'));

    final samplePng = File(p.join(temp.path, 'equirectangular.png'));
    await tester.runAsync(
      () => samplePng.writeAsBytes(_png(width: 4, height: 2)),
    );
    FileSelectorPlatform.instance = FakeFileSelector(
      file: XFile(samplePng.path),
    );

    await _pumpForm(tester, container);

    await tester.tap(find.byKey(const Key('world-import-layer')));
    await tester.pump();

    expect(
      find.byKey(const Key('world-import-layer-progress')),
      findsOneWidget,
    );
    expect(find.text('Importing…'), findsOneWidget);
    final button = tester.widget<DsButton>(
      find.byKey(const Key('world-import-layer')),
    );
    expect(button.onPressed, isNull);

    repository.result.complete(
      const WorldLayer(
        id: 'layer-1',
        kind: WorldLayerKind.heightmap,
        assetId: 'heightmap.png',
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Import PNG layer'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('shows the equirectangular validation error', (tester) async {
    final (container, _) = await openTestKb(
      tester,
      temp,
      name: 'Awayside',
      overrides: [
        worldAssetRepositoryProvider.overrideWith(
          (ref) => ThrowingWorldAssetRepository(
            ref.watch(kbSessionProvider)!.kb,
            const KbException(
              'A World layer must be equirectangular (2:1). Found 4×3; '
              'expected 6×3.',
            ),
          ),
        ),
      ],
    );
    final controller = container.read(openWorldProvider.notifier);
    await tester.runAsync(() => controller.setEngine('orogen'));

    final samplePng = File(p.join(temp.path, 'not-equirectangular.png'));
    await tester.runAsync(
      () => samplePng.writeAsBytes(_png(width: 4, height: 3)),
    );
    FileSelectorPlatform.instance = FakeFileSelector(
      file: XFile(samplePng.path),
    );
    await _pumpForm(tester, container);

    await tester.tap(find.byKey(const Key('world-import-layer')));
    await tester.pump();

    expect(
      find.text(
        'A World layer must be equirectangular (2:1). Found 4×3; '
        'expected 6×3.',
      ),
      findsOneWidget,
    );
    expect(container.read(openWorldProvider)!.world.layers, isEmpty);
  });

  testWidgets('shows unexpected picker errors', (tester) async {
    final (container, _) = await openTestKb(tester, temp, name: 'Awayside');
    final controller = container.read(openWorldProvider.notifier);
    await tester.runAsync(() => controller.setEngine('orogen'));

    FileSelectorPlatform.instance = FakeFileSelector(
      error: StateError('picker failed'),
    );
    await _pumpForm(tester, container);

    await tester.tap(find.byKey(const Key('world-import-layer')));
    await tester.pump();

    expect(
      find.text('Could not import the PNG layer: Bad state: picker failed'),
      findsOneWidget,
    );
    expect(find.text('Import PNG layer'), findsOneWidget);
  });
}

Future<void> _pumpForm(WidgetTester tester, ProviderContainer container) =>
    tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: OrogenSettingsForm()),
        ),
      ),
    );

const _pngSignature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

List<int> _png({required int width, required int height}) => [
  ..._pngSignature,
  ..._chunk('IHDR', [..._uint32(width), ..._uint32(height), 8, 0, 0, 0, 0]),
  ..._chunk('IEND', const []),
];

List<int> _chunk(String type, List<int> data) => [
  ..._uint32(data.length),
  ...type.codeUnits,
  ...data,
  0,
  0,
  0,
  0,
];

List<int> _uint32(int value) => [
  (value >> 24) & 0xff,
  (value >> 16) & 0xff,
  (value >> 8) & 0xff,
  value & 0xff,
];
