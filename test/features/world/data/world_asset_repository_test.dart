import 'dart:io';

import 'package:dayseven/features/world/data/world_asset_repository.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late KnowledgeBase kb;
  late WorldAssetRepository repository;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_world_asset_test');
    final bundle = Directory(p.join(temp.path, 'bundle'));
    await bundle.create();
    kb = await KnowledgeBase.create(folder: bundle.path, name: 'MyWorld');
    repository = WorldAssetRepository(kb);
  });

  tearDown(() async {
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<File> sourceFile(String name, {int width = 4, int height = 2}) async {
    final file = File(p.join(temp.path, name));
    await file.writeAsBytes(_png(width: width, height: height));
    return file;
  }

  Future<WorldLayer> importSource(File source) => repository.importLayer(
    id: 'layer-1',
    kind: WorldLayerKind.heightmap,
    source: source,
  );

  test('refuses a file renamed to jpg', () async {
    final source = await sourceFile('heightmap.jpg');

    expect(importSource(source), throwsA(isA<KbException>()));
  });

  test('refuses a non-equirectangular PNG before copying it', () async {
    final source = await sourceFile('heightmap.png', width: 4, height: 3);

    expect(importSource(source), throwsA(isA<KbException>()));

    final assets = Directory(kb.assetsPath)
        .listSync()
        .whereType<File>()
        .toList();
    expect(assets, isEmpty);
  });

  test('imports a valid PNG and attaches stored metadata', () async {
    final source = await sourceFile('heightmap.png');

    final layer = await importSource(source);

    expect(layer.id, 'layer-1');
    expect(layer.kind, WorldLayerKind.heightmap);
    expect(layer.assetId, endsWith('.png'));
    expect(layer.metadata, isNotNull);
    expect(layer.metadata!.width, 4);
    expect(layer.metadata!.height, 2);
    expect(layer.metadata!.isGreyscale, isTrue);
    expect(File(kb.assetPathFor(layer.assetId)).existsSync(), isTrue);
  });
}

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
