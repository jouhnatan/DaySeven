/// World/Economy object replication through the hierarchy replicator.
library;

import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_hierarchy_replicator.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/object_repository.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/economy.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/object_sync_fakes.dart';

class _NoDocuments extends DocumentRepository {
  @override
  Future<List<RemoteDocumentSnapshot>> snapshot(String kbId) async => const [];
}

class _RecordingAssets extends AssetRepository {
  final List<String> uploadedObjects = [];
  final List<String> downloadedObjects = [];

  @override
  Future<void> uploadReferenced({
    required KnowledgeBase kb,
    required BlockDocument document,
  }) async {}

  @override
  Future<void> downloadMissing({
    required KnowledgeBase kb,
    required BlockDocument document,
  }) async {}

  @override
  Future<void> uploadReferencedObject({
    required KnowledgeBase kb,
    required Object? json,
  }) async {
    uploadedObjects.addAll(referencedByObject(json));
  }

  @override
  Future<void> downloadMissingObject({
    required KnowledgeBase kb,
    required Object? json,
  }) async {
    downloadedObjects.addAll(referencedByObject(json));
  }
}

class _ConflictingObjects extends FakeObjectRepository {
  _ConflictingObjects({required this.conflictingId});

  final String conflictingId;

  @override
  Future<String> publish({
    required String kbId,
    required String objectId,
    required String kind,
    required String path,
    required String title,
    required Map<String, Object?> content,
    required String contentHash,
    required String? expectedCurrentRevisionId,
  }) async {
    if (objectId == conflictingId) {
      throw const PostgrestException(
        message: 'object moved on; refresh before publishing',
        code: '40001',
        details: 'Conflict',
        hint: 'Refresh the canonical revision before publishing again.',
      );
    }
    return super.publish(
      kbId: kbId,
      objectId: objectId,
      kind: kind,
      path: path,
      title: title,
      content: content,
      contentHash: contentHash,
      expectedCurrentRevisionId: expectedCurrentRevisionId,
    );
  }
}

World world({String id = 'world-1', int population = 100}) => World(
  id: id,
  title: 'Aster',
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
    landmarks: [
      Model3DLandmark(id: 'c1', name: 'Aldenmoor', latitude: 0, longitude: 0),
    ],
  ),
  economy: WorldEconomy.seeded().withLocation(
    EconomyLocation(id: 'e1', landmarkId: 'c1', population: population),
  ),
);

RemoteObjectSnapshot remoteSnapshot(
  World value, {
  required String revisionId,
  String path = 'Aster.unearth',
}) => RemoteObjectSnapshot(
  id: value.id,
  kind: World.kind,
  path: path,
  revisionId: revisionId,
  content: value.toJson(),
  contentHash: canonicalObjectHash(value.toJson()),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late KnowledgeBase kb;
  late SearchIndex index;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_object_sync');
    kb = await KnowledgeBase.create(
      folder: temp.path,
      name: 'Shared KB',
      kbId: 'kb-objects',
    );
    index = await SearchIndex.openFor(kb);
    await index.rebuild();
  });

  tearDown(() async {
    index.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<ProviderContainer> containerFor({
    required FakeObjectRepository objects,
    _RecordingAssets? assets,
  }) async {
    final session = KbSession(kb: kb, index: index, tree: await kb.readTree());
    return ProviderContainer(
      overrides: [
        kbSessionProvider.overrideWithValue(session),
        documentRepositoryProvider.overrideWithValue(_NoDocuments()),
        objectRepositoryProvider.overrideWithValue(objects),
        assetRepositoryProvider.overrideWithValue(assets ?? _RecordingAssets()),
        kbRoleProvider.overrideWith((ref) async => KbRole.owner),
        differencesNetworkEnabledProvider.overrideWithValue(true),
        differencesRealtimeEnabledProvider.overrideWithValue(false),
        appStoreProvider.overrideWith(
          (ref) async => AppStore(File('${kb.rootPath}.app-store.json')),
        ),
      ],
    );
  }

  test(
    'pull writes the canonical World, its map asset and the ledger',
    () async {
      final canonical = world();
      final objects = FakeObjectRepository(
        snapshots: [remoteSnapshot(canonical, revisionId: 'rev-1')],
      );
      final assets = _RecordingAssets();
      final container = await containerFor(objects: objects, assets: assets);
      addTearDown(container.dispose);

      final result = await container
          .read(kbHierarchyReplicatorProvider)
          .ensureLocalMatchesRemote();

      expect(result.updated, 1);
      expect(result.conflicts, 0);
      final stored = World.fromJson(await kb.readObjectJson('Aster.unearth'));
      expect(stored.economy.locationForLandmark('c1')!.population, 100);
      expect(assets.downloadedObjects, contains('map.png'));
      final ledger = await SyncLedger.open(kb);
      expect(ledger.object('world-1')?.revisionId, 'rev-1');
      expect(ledger.object('world-1')?.path, 'Aster.unearth');
    },
  );

  test('pull keeps a divergent local World and counts a conflict', () async {
    final local = world(population: 900);
    await kb.createObject(name: 'Aster', seed: local.toJson());
    final base = world(population: 100);
    final ledger = await SyncLedger.open(kb);
    await ledger.recordObject(
      objectId: 'world-1',
      revisionId: 'rev-1',
      contentHash: canonicalObjectHash(base.toJson()),
      path: 'Aster.unearth',
    );

    final objects = FakeObjectRepository(
      snapshots: [remoteSnapshot(world(population: 500), revisionId: 'rev-2')],
    );
    final container = await containerFor(objects: objects);
    addTearDown(container.dispose);

    final result = await container
        .read(kbHierarchyReplicatorProvider)
        .ensureLocalMatchesRemote();

    expect(result.conflicts, 1);
    expect(result.updated, 0);
    final preserved = World.fromJson(await kb.readObjectJson('Aster.unearth'));
    expect(preserved.economy.locationForLandmark('c1')!.population, 900);
  });

  test(
    'push publishes a local World with its map asset and records the base',
    () async {
      final local = world(population: 250);
      await kb.createObject(name: 'Aster', seed: local.toJson());
      final objects = FakeObjectRepository();
      final assets = _RecordingAssets();
      final container = await containerFor(objects: objects, assets: assets);
      addTearDown(container.dispose);

      final result = await container
          .read(kbHierarchyReplicatorProvider)
          .ensureRemoteMatchesLocal();

      expect(result.published, 1);
      expect(objects.published.single.id, 'world-1');
      expect(objects.published.single.path, 'Aster.unearth');
      expect(
        objects.published.single.contentHash,
        canonicalObjectHash(local.toJson()),
      );
      expect(assets.uploadedObjects, contains('map.png'));
      final ledger = await SyncLedger.open(kb);
      expect(ledger.object('world-1')?.revisionId, 'object-revision-1');
    },
  );

  test(
    'push counts one lost race as a conflict and publishes the rest',
    () async {
      await kb.createObject(
        name: 'Aster',
        seed: world(id: 'world-1').toJson(),
      );
      await kb.createObject(
        name: 'Brim',
        seed: world(id: 'world-2').toJson(),
      );
      final objects = _ConflictingObjects(conflictingId: 'world-1');
      final container = await containerFor(objects: objects);
      addTearDown(container.dispose);

      final result = await container
          .read(kbHierarchyReplicatorProvider)
          .ensureRemoteMatchesLocal();

      expect(result.conflicts, 1);
      expect(result.published, 1);
      expect(objects.published.single.id, 'world-2');
      expect(await File(kb.absolutePathFor('Aster.unearth')).exists(), isTrue);
    },
  );

  test('a canonically deleted World moves to recovery, not the bin', () async {
    final local = world();
    await kb.createObject(name: 'Aster', seed: local.toJson());
    final ledger = await SyncLedger.open(kb);
    await ledger.recordObject(
      objectId: 'world-1',
      revisionId: 'rev-1',
      contentHash: canonicalObjectHash(local.toJson()),
      path: 'Aster.unearth',
    );

    final container = await containerFor(objects: FakeObjectRepository());
    addTearDown(container.dispose);

    final result = await container
        .read(kbHierarchyReplicatorProvider)
        .ensureLocalMatchesRemote();

    expect(result.recoveredDeletions, 1);
    expect(await File(kb.absolutePathFor('Aster.unearth')).exists(), isFalse);
    final recovery = File(
      p.join(kb.settingsPath, 'recovery', 'world-1', 'Aster.unearth'),
    );
    expect(await recovery.exists(), isTrue);
  });

  test('pull follows a canonical rename and removes the old file', () async {
    final local = world();
    await kb.createObject(name: 'Old', seed: local.toJson());
    final ledger = await SyncLedger.open(kb);
    await ledger.recordObject(
      objectId: 'world-1',
      revisionId: 'rev-1',
      contentHash: canonicalObjectHash(local.toJson()),
      path: 'Old.unearth',
    );

    final objects = FakeObjectRepository(
      snapshots: [
        remoteSnapshot(world(), revisionId: 'rev-2', path: 'New.unearth'),
      ],
    );
    final container = await containerFor(objects: objects);
    addTearDown(container.dispose);

    final result = await container
        .read(kbHierarchyReplicatorProvider)
        .ensureLocalMatchesRemote();

    expect(result.updated, 1);
    expect(await File(kb.absolutePathFor('Old.unearth')).exists(), isFalse);
    expect(await File(kb.absolutePathFor('New.unearth')).exists(), isTrue);
    expect((await SyncLedger.open(kb)).object('world-1')?.path, 'New.unearth');
  });

  test('push publishes a local rename against the old path revision', () async {
    final local = world();
    await kb.createObject(name: 'New', seed: local.toJson());
    final ledger = await SyncLedger.open(kb);
    await ledger.recordObject(
      objectId: 'world-1',
      revisionId: 'rev-1',
      contentHash: canonicalObjectHash(local.toJson()),
      path: 'Old.unearth',
    );

    final objects = FakeObjectRepository(
      snapshots: [
        remoteSnapshot(local, revisionId: 'rev-1', path: 'Old.unearth'),
      ],
    );
    final container = await containerFor(objects: objects);
    addTearDown(container.dispose);

    final result = await container
        .read(kbHierarchyReplicatorProvider)
        .ensureRemoteMatchesLocal();

    expect(result.published, 1);
    expect(objects.published.single.path, 'New.unearth');
    expect((await SyncLedger.open(kb)).object('world-1')?.path, 'New.unearth');
  });
}
