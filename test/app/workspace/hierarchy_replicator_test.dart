import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_hierarchy_replicator.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/revision.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAssetRepository extends AssetRepository {
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
}

class FakeDocuments extends DocumentRepository {
  FakeDocuments({this.snapshots = const []});
  List<RemoteDocumentSnapshot> snapshots;
  final List<RemoteDocumentSnapshot> published = [];
  Map<String, RemoteDocumentSnapshot> byId = {};
  int publishCalls = 0;

  @override
  Future<List<RemoteDocumentSnapshot>> snapshot(String kbId) async => snapshots;

  @override
  Future<RemoteDocumentSnapshot?> snapshotForDocument(
    String documentId,
  ) async =>
      byId[documentId] ??
      snapshots.where((s) => s.document.id == documentId).firstOrNull;

  @override
  Future<DocumentPublishReceipt> publishChange({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) async {
    publishCalls++;
    final snap = RemoteDocumentSnapshot(
      path: relativePath,
      revisionId: 'rev-$publishCalls',
      document: document,
    );
    published.add(snap);
    byId[document.id] = snap;
    snapshots = [
      for (final existing in snapshots)
        if (existing.document.id != document.id) existing,
      snap,
    ];
    return DocumentPublishReceipt.published(snap.revisionId);
  }

  @override
  Future<String?> currentRevisionId(String documentId) async =>
      byId[documentId]?.revisionId;

  @override
  Future<Revision?> revision(String revisionId) async => null;

  @override
  Future<List<Map<String, Object?>>> documentsIn(String kbId) async => [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('KbHierarchyReplicator', () {
    late Directory tempA;
    late Directory tempB;
    late KnowledgeBase kbA;
    late KnowledgeBase kbB;
    late SearchIndex indexA;
    late SearchIndex indexB;

    setUp(() async {
      tempA = await Directory.systemTemp.createTemp('hierarchy_replicator_A');
      tempB = await Directory.systemTemp.createTemp('hierarchy_replicator_B');
      // Same kbId to simulate same shared KB on two devices
      const kbId = 'kb-alwayside';
      kbA = await KnowledgeBase.create(
        folder: tempA.path,
        name: 'Awayside',
        kbId: kbId,
      );
      kbB = await KnowledgeBase.create(
        folder: tempB.path,
        name: 'Awayside',
        kbId: kbId,
      );
      indexA = await SearchIndex.openFor(kbA);
      indexB = await SearchIndex.openFor(kbB);
      await indexA.rebuild();
      await indexB.rebuild();
    });

    tearDown(() async {
      indexA.close();
      indexB.close();
      if (await tempA.exists()) await tempA.delete(recursive: true);
      if (await tempB.exists()) await tempB.delete(recursive: true);
    });

    Future<ProviderContainer> makeContainer(
      KnowledgeBase kb,
      SearchIndex index,
      FakeDocuments docs,
    ) async {
      final session = KbSession(
        kb: kb,
        index: index,
        tree: await kb.readTree(),
      );
      return ProviderContainer(
        overrides: [
          kbSessionProvider.overrideWithValue(session),
          documentRepositoryProvider.overrideWithValue(docs),
          assetRepositoryProvider.overrideWithValue(FakeAssetRepository()),
          kbRoleProvider.overrideWith((ref) async => KbRole.owner),
          differencesNetworkEnabledProvider.overrideWithValue(true),
          differencesRealtimeEnabledProvider.overrideWithValue(false),
          appStoreProvider.overrideWith(
            (ref) async => AppStore(File('${kb.rootPath}.app-store.json')),
          ),
        ],
      );
    }

    test('publishing Untitled in Awayside replicates hierarchy and data on peer', () async {
      // Device A: create Awayside folder + Untitled.md and publish via replicator push
      await kbA.createFolder('Awayside');
      final pathA = await kbA.createDocument(
        title: 'Untitled',
        folderRelativePath: 'Awayside',
      );
      // pathA should be Awayside/Untitled.md
      expect(pathA, 'Awayside/Untitled.md');
      final docA = await kbA.readDocument(pathA);
      // Simulate canonical state after publish
      final fakeDocs = FakeDocuments(
        snapshots: [
          RemoteDocumentSnapshot(
            path: pathA,
            revisionId: 'rev-1',
            document: docA,
          ),
        ],
      );

      // Device B: empty, no Awayside folder
      expect(await Directory('${tempB.path}/Awayside').exists(), isFalse);
      expect(
        await File('${tempB.path}/Awayside/Untitled.md').exists(),
        isFalse,
      );

      final containerB = await makeContainer(kbB, indexB, fakeDocs);
      addTearDown(containerB.dispose);

      // Pull via replicator – this is what the Knowledge Base Sync button does.
      final replicator = containerB.read(kbHierarchyReplicatorProvider);
      final pull = await replicator.ensureLocalMatchesRemote();

      expect(pull.updated, 1);
      expect(pull.conflicts, 0);
      // Hierarchy replicated
      expect(await Directory('${tempB.path}/Awayside').exists(), isTrue);
      expect(await File('${tempB.path}/Awayside/Untitled.md').exists(), isTrue);
      final docB = await kbB.readDocument('Awayside/Untitled.md');
      expect(docB.title, 'Untitled');
      expect(docB.id, docA.id);
      expect(docB.contentHash, docA.contentHash);
      // Tree refreshed
      final treeB = await kbB.readTree();
      final pathsB = documentPathsIn(treeB).toList();
      expect(pathsB, contains('Awayside/Untitled.md'));
      // Ledger recorded
      final ledgerB = await SyncLedger.open(kbB);
      expect(ledgerB.document(docA.id)?.path, 'Awayside/Untitled.md');
      expect(ledgerB.document(docA.id)?.revisionId, 'rev-1');
    });

    test(
      'nested hierarchy Awayside/Lore/Untitled replicates parents recursively',
      () async {
        await kbA.createFolder('Awayside/Lore');
        final pathA = await kbA.createDocument(
          title: 'Untitled',
          folderRelativePath: 'Awayside/Lore',
        );
        expect(pathA, 'Awayside/Lore/Untitled.md');
        final docA = await kbA.readDocument(pathA);
        final fakeDocs = FakeDocuments(
          snapshots: [
            RemoteDocumentSnapshot(
              path: pathA,
              revisionId: 'rev-nested',
              document: docA,
            ),
          ],
        );
        final containerB = await makeContainer(kbB, indexB, fakeDocs);
        addTearDown(containerB.dispose);
        final replicator = containerB.read(kbHierarchyReplicatorProvider);
        final pull = await replicator.ensureLocalMatchesRemote();
        expect(pull.updated, 1);
        expect(await Directory('${tempB.path}/Awayside').exists(), isTrue);
        expect(await Directory('${tempB.path}/Awayside/Lore').exists(), isTrue);
        expect(
          await File('${tempB.path}/Awayside/Lore/Untitled.md').exists(),
          isTrue,
        );
        final docB = await kbB.readDocument(pathA);
        expect(docB.sameContentAs(docA), isTrue);
      },
    );

    test('does not overwrite divergent local file – counts as conflict', () async {
      // Device A has canonical Awayside/Untitled.md with rev-2
      await kbA.createFolder('Awayside');
      final pathA = await kbA.createDocument(
        title: 'Untitled',
        folderRelativePath: 'Awayside',
      );
      final canonicalDoc = (await kbA.readDocument(pathA)).copyWith(
        blocks: [
          ParagraphBlock(
            id: 'p1',
            spans: [TextSpanNode(text: 'Canonical')],
          ),
        ],
      );
      await kbA.writeDocument(pathA, canonicalDoc);
      final fakeDocs = FakeDocuments(
        snapshots: [
          RemoteDocumentSnapshot(
            path: pathA,
            revisionId: 'rev-2',
            document: canonicalDoc,
          ),
        ],
      );
      // Device B has same path but divergent local edit, with ledger at rev-1
      await kbB.createFolder('Awayside');
      final pathB = await kbB.createDocument(
        title: 'Untitled',
        folderRelativePath: 'Awayside',
      );
      // Ensure same id to simulate same document diverging? Use canonical's id
      // For test, write divergent doc with same id as canonical but different content
      final divergent = BlockDocument(
        id: canonicalDoc.id,
        title: 'Untitled',
        blocks: [
          ParagraphBlock(
            id: 'p1',
            spans: [TextSpanNode(text: 'Divergent local edits')],
          ),
        ],
      );
      await kbB.writeDocument(pathB, divergent);
      final ledgerB = await SyncLedger.open(kbB);
      await ledgerB.record(
        document: divergent,
        revisionId: 'rev-1',
        path: pathB,
      );
      // But canonical is rev-2 different content, ledger base is rev-1
      // So pull should detect localHash != ledgerHash? Actually ledger hash == divergent hash,
      // but canonical is newer. Logic: previous.contentHash == localHash? divergent hash == ledger hash => not conflict? Wait.
      // To trigger conflict, divergent hash != ledger hash? Let's make ledger at old canonical base, local is diverged.
      // Rebuild ledger with old base hash different from current divergent
      final oldBase = BlockDocument(
        id: canonicalDoc.id,
        title: 'Untitled',
        blocks: [
          ParagraphBlock(
            id: 'p1',
            spans: [TextSpanNode(text: 'Base')],
          ),
        ],
      );
      await ledgerB.record(document: oldBase, revisionId: 'rev-1', path: pathB);
      // Now local file is divergent (different hash than ledger's oldBase)
      // Pull should see localHash != previous.contentHash => conflict

      final containerB = await makeContainer(kbB, indexB, fakeDocs);
      addTearDown(containerB.dispose);
      final replicator = containerB.read(kbHierarchyReplicatorProvider);
      final pull = await replicator.ensureLocalMatchesRemote();
      expect(pull.conflicts, 1);
      expect(pull.updated, 0);
      // Local file preserved byte-for-byte
      final preserved = await kbB.readDocument(pathB);
      expect(preserved.plainText, 'Divergent local edits');
    });

    test(
      'ensureRemoteMatchesLocal publishes missing local hierarchy to canonical',
      () async {
        // Device A has local hierarchy Awayside/Untitled.md not yet in snapshot
        await kbA.createFolder('Awayside');
        final pathA = await kbA.createDocument(
          title: 'Untitled',
          folderRelativePath: 'Awayside',
        );
        final docA = await kbA.readDocument(pathA);
        final docs = FakeDocuments(snapshots: []);
        final sessionA = KbSession(
          kb: kbA,
          index: indexA,
          tree: await kbA.readTree(),
        );
        final containerA = ProviderContainer(
          overrides: [
            kbSessionProvider.overrideWithValue(sessionA),
            documentRepositoryProvider.overrideWithValue(docs),
            assetRepositoryProvider.overrideWithValue(FakeAssetRepository()),
            kbRoleProvider.overrideWith((ref) async => KbRole.owner),
            differencesNetworkEnabledProvider.overrideWithValue(true),
            differencesRealtimeEnabledProvider.overrideWithValue(false),
            appStoreProvider.overrideWith(
              (ref) async => AppStore(File('${tempA.path}.app-store.json')),
            ),
          ],
        );
        addTearDown(containerA.dispose);
        final replicator = containerA.read(kbHierarchyReplicatorProvider);
        final push = await replicator.ensureRemoteMatchesLocal();
        expect(push.published, 1);
        expect(docs.published.single.path, 'Awayside/Untitled.md');
        expect(docs.published.single.document.id, docA.id);
        // Ledger now reflects published
        final ledgerA = await SyncLedger.open(kbA);
        expect(ledgerA.document(docA.id)?.path, 'Awayside/Untitled.md');
      },
    );

    test('reconcile pulls then pushes', () async {
      // Start with B having canonical, A having extra local doc
      await kbA.createFolder('Awayside');
      final pathA = await kbA.createDocument(
        title: 'Untitled',
        folderRelativePath: 'Awayside',
      );
      await kbA.readDocument(pathA);
      // Canonical has different doc Lore.md
      final loreDoc = BlockDocument(
        id: 'lore-id',
        title: 'Lore',
        blocks: [
          ParagraphBlock(
            id: 'p2',
            spans: [TextSpanNode(text: 'Lore text')],
          ),
        ],
      );
      final fakeDocs = FakeDocuments(
        snapshots: [
          RemoteDocumentSnapshot(
            path: 'Lore.md',
            revisionId: 'rev-lore',
            document: loreDoc,
          ),
        ],
      );
      // Pre-create ledger for A with no entry for Lore, and no remote for Untitled
      final sessionA = KbSession(
        kb: kbA,
        index: indexA,
        tree: await kbA.readTree(),
      );
      final containerA = ProviderContainer(
        overrides: [
          kbSessionProvider.overrideWithValue(sessionA),
          documentRepositoryProvider.overrideWithValue(fakeDocs),
          assetRepositoryProvider.overrideWithValue(FakeAssetRepository()),
          kbRoleProvider.overrideWith((ref) async => KbRole.owner),
          differencesNetworkEnabledProvider.overrideWithValue(true),
          differencesRealtimeEnabledProvider.overrideWithValue(false),
          appStoreProvider.overrideWith(
            (ref) async => AppStore(File('${tempA.path}.app-store.json')),
          ),
        ],
      );
      addTearDown(containerA.dispose);
      final replicator = containerA.read(kbHierarchyReplicatorProvider);
      final result = await replicator.reconcile();
      expect(result.pull.updated, 1); // pulled Lore.md, creating hierarchy root
      expect(result.push.published, 1); // pushed Awayside/Untitled.md
      expect(await File('${tempA.path}/Lore.md').exists(), isTrue);
      expect(
        fakeDocs.published.any((s) => s.path == 'Awayside/Untitled.md'),
        isTrue,
      );
    });

    test('reconcile after a local rename publishes the renamed path without recreating the old path', () async {
      final initialDoc = BlockDocument(
        id: 'doc-aldenmoor',
        title: 'Aldenmoor',
        blocks: [
          ParagraphBlock(
            id: 'p1',
            spans: const [TextSpanNode(text: 'Aldenmoor text')],
          ),
        ],
      );
      final fakeDocs = FakeDocuments(
        snapshots: [
          RemoteDocumentSnapshot(
            path: 'Aldenmoor.md',
            revisionId: 'rev-1',
            document: initialDoc,
          ),
        ],
      );

      final containerA = await makeContainer(kbA, indexA, fakeDocs);
      addTearDown(containerA.dispose);
      final replicator = containerA.read(kbHierarchyReplicatorProvider);

      final pullResult = await replicator.ensureLocalMatchesRemote();
      expect(pullResult.updated, 1);
      expect(await File('${tempA.path}/Aldenmoor.md').exists(), isTrue);

      final destination = await kbA.renameDocument('Aldenmoor.md', 'Ammur-ili');
      expect(destination, 'Ammur-ili.md');
      indexA.rename('Aldenmoor.md', 'Ammur-ili.md');

      final result = await replicator.reconcile();
      expect(result.pull.updated, 0);
      expect(result.pull.conflicts, 0);
      expect(result.push.published, 1);

      expect(await File('${tempA.path}/Aldenmoor.md').exists(), isFalse);
      expect(await File('${tempA.path}/Ammur-ili.md').exists(), isTrue);

      final remote = await fakeDocs.snapshot('kb-alwayside');
      expect(remote, hasLength(1));
      expect(remote.single.path, 'Ammur-ili.md');
      expect(remote.single.document.id, 'doc-aldenmoor');
    });

    test(
      'concurrent reconcile/pull calls share one active operation',
      () async {
        final fakeDocs = FakeDocuments(snapshots: []);
        final containerA = await makeContainer(kbA, indexA, fakeDocs);
        addTearDown(containerA.dispose);

        final sharing = containerA.read(sharingControllerProvider);

        final pull1 = sharing.pullRemoteChanges();
        final pull2 = sharing.pullRemoteChanges();
        expect(identical(pull1, pull2), isTrue);
        final pullRes = await pull1;
        expect(pullRes.updated, 0);

        final rec1 = sharing.reconcileHierarchy();
        final rec2 = sharing.reconcileHierarchy();
        expect(identical(rec1, rec2), isTrue);
        final recRes = await rec1;
        expect(recRes.pull.updated, 0);
      },
    );
  });
}
