import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/data/change_set_repository.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/revision.dart';
import 'package:dayseven/shared/blocks/search_index.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const user = User(
  id: '11111111-1111-4111-8111-111111111111',
  appMetadata: {},
  userMetadata: {'username': 'local-author'},
  aud: 'authenticated',
  createdAt: '2026-08-22T00:00:00Z',
);

ChangeSet change({
  required String id,
  required String authorId,
  String documentId = 'doc-1',
  String username = 'collaborator',
  BlockDocument? content,
}) => ChangeSet(
  id: id,
  kbId: 'kb-1',
  documentId: documentId,
  targetDocumentId: documentId,
  baseRevisionId: 'base-1',
  content:
      content ??
      BlockDocument(id: documentId, title: 'Aldenmoor', blocks: const []),
  authorId: authorId,
  authorUsername: username,
  authorDisplayName: username,
  status: ChangeSetStatus.pending,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
);

class FakeChangeSets implements ChangeSetDataSource {
  List<ChangeSet> pending = [];
  Object? pendingError;
  Object? proposalError;
  int proposals = 0;
  int withdrawals = 0;
  int creates = 0;
  int deletes = 0;
  BlockDocument? latestContent;
  String? latestPath;

  @override
  Future<List<ChangeSet>> pendingForKb(String kbId) async {
    final error = pendingError;
    if (error != null) throw error;
    return pending;
  }

  @override
  Future<ChangeSet> propose({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    String? relativePath,
    required BlockDocument content,
  }) async {
    final error = proposalError;
    if (error != null) throw error;
    proposals++;
    latestContent = content;
    latestPath = relativePath;
    return change(
      id: 'stable-pending-id',
      authorId: user.id,
      documentId: documentId,
      username: 'local-author',
      content: content,
    );
  }

  @override
  Future<ChangeSet> proposeCreate({
    required String kbId,
    required String relativePath,
    required BlockDocument content,
  }) async {
    creates++;
    return propose(
      kbId: kbId,
      documentId: content.id,
      baseRevisionId: 'base-1',
      relativePath: relativePath,
      content: content,
    );
  }

  @override
  Future<ChangeSet> proposeDelete({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    required String relativePath,
  }) async {
    deletes++;
    latestPath = relativePath;
    return change(
      id: 'delete-proposal',
      authorId: user.id,
      documentId: documentId,
    );
  }

  @override
  Future<ChangeSet?> byId(String changeSetId) async => null;

  @override
  Future<String?> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
    String? reviewNote,
  }) async => 'revision-approved';

  @override
  Future<void> reject(String changeSetId, {String? reviewNote}) async {}

  @override
  Future<void> withdrawForDocument({
    required String kbId,
    required String documentId,
  }) async {
    withdrawals++;
  }
}

class FakeDocuments extends DocumentRepository {
  FakeDocuments({required this.role});

  final KbRole role;
  String? current = 'base-1';
  int commits = 0;
  int deletions = 0;
  BlockDocument? currentDocument;
  String currentPath = 'Aldenmoor.md';
  DocumentProtection? currentProtection;
  final Map<String, Revision> revisions = {};

  @override
  Future<String?> currentRevisionId(String documentId) async => current;

  @override
  Future<RemoteDocumentSnapshot?> snapshotForDocument(String documentId) async {
    if (current == null || currentDocument == null) return null;
    return RemoteDocumentSnapshot(
      path: currentPath,
      revisionId: current!,
      document: currentDocument!,
      protection: currentProtection,
    );
  }

  @override
  Future<List<RemoteDocumentSnapshot>> snapshot(String kbId) async {
    final one = await snapshotForDocument(currentDocument?.id ?? 'missing');
    return one == null ? const [] : [one];
  }

  @override
  Future<Revision?> revision(String revisionId) async => revisions[revisionId];

  @override
  Future<DocumentProtection?> protection(String documentId) async =>
      currentProtection;

  @override
  Future<DocumentPublishReceipt> publishChange({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) async {
    final mayPublish =
        currentProtection == null ||
        role.meets(currentProtection!.minimumPublishRole);
    if (!mayPublish) {
      return const DocumentPublishReceipt.proposed('stable-pending-id');
    }
    commits++;
    current = 'revision-$commits';
    currentDocument = document;
    currentPath = relativePath;
    return DocumentPublishReceipt.published(current!);
  }

  @override
  Future<DocumentPublishReceipt> publishDeletion({
    required String kbId,
    required String documentId,
    required String relativePath,
    required String expectedCurrentRevisionId,
  }) async {
    deletions++;
    final mayPublish =
        currentProtection == null ||
        role.meets(currentProtection!.minimumPublishRole);
    return mayPublish
        ? DocumentPublishReceipt.published(documentId)
        : const DocumentPublishReceipt.proposed('delete-proposal');
  }

  @override
  Future<DocumentProtection?> setProtection({
    required String kbId,
    required String documentId,
    DocumentProtection? protection,
  }) async {
    currentProtection = protection;
    return protection;
  }

  @override
  Future<String> commit({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
  }) async {
    commits++;
    current = 'revision-$commits';
    currentDocument = document;
    currentPath = relativePath;
    return current!;
  }

  @override
  Future<String> publish({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
  }) => commit(kbId: kbId, relativePath: relativePath, document: document);

  @override
  Future<String> publishDirect({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) => commit(kbId: kbId, relativePath: relativePath, document: document);
}

class TestContext {
  TestContext({
    required this.directory,
    required this.kb,
    required this.index,
    required this.path,
    required this.base,
    required this.changes,
    required this.documents,
    required this.container,
  });

  final Directory directory;
  final KnowledgeBase kb;
  final SearchIndex index;
  final String path;
  final BlockDocument base;
  final FakeChangeSets changes;
  final FakeDocuments documents;
  final ProviderContainer container;

  Future<void> close() async {
    container.dispose();
    index.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Future<TestContext> context({KbRole role = KbRole.editor}) async {
  final directory = await Directory.systemTemp.createTemp('differences_test');
  final kb = await KnowledgeBase.create(
    folder: directory.path,
    name: 'World',
    kbId: 'kb-1',
  );
  final base = BlockDocument(
    id: 'doc-1',
    title: 'Aldenmoor',
    blocks: const [
      ParagraphBlock(
        id: 'p-1',
        spans: [TextSpanNode(text: 'Base words')],
      ),
    ],
  );
  final path = await kb.createDocument(title: 'Aldenmoor');
  await kb.writeDocument(path, base);
  final ledger = await SyncLedger.open(kb);
  await ledger.record(document: base, revisionId: 'base-1', path: path);
  final index = await SearchIndex.openFor(kb);
  await index.rebuild();
  final changes = FakeChangeSets();
  final documents = FakeDocuments(role: role)
    ..currentDocument = base
    ..currentPath = path
    ..revisions['base-1'] = Revision(
      id: 'base-1',
      documentId: base.id,
      parentRevisionId: null,
      content: base,
      contentHash: base.contentHash,
      authorId: 'owner',
      createdAt: DateTime.utc(2026, 8, 22),
    );
  final session = KbSession(kb: kb, index: index, tree: await kb.readTree());
  final container = ProviderContainer(
    overrides: [
      currentUserProvider.overrideWithValue(user),
      kbSessionProvider.overrideWithValue(session),
      kbRoleProvider.overrideWith((ref) async => role),
      differencesNetworkEnabledProvider.overrideWithValue(true),
      differencesRealtimeEnabledProvider.overrideWithValue(false),
      changeSetRepositoryProvider.overrideWithValue(changes),
      documentRepositoryProvider.overrideWithValue(documents),
      appStoreProvider.overrideWith(
        (ref) async => AppStore(File('${directory.path}/app-store.json')),
      ),
    ],
  );
  await container.read(documentControllerProvider.notifier).open(path);
  return TestContext(
    directory: directory,
    kb: kb,
    index: index,
    path: path,
    base: base,
    changes: changes,
    documents: documents,
    container: container,
  );
}

Future<void> settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'editing and local autosave never transmit without an explicit action',
    () async {
      final test = await context();
      addTearDown(test.close);
      test.container.read(differencesControllerProvider);
      final edited = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Local only until Publish')],
          ),
        ],
      );

      test.container.read(documentControllerProvider.notifier).edit(edited);
      await Future<void>.delayed(const Duration(milliseconds: 1900));
      await test.container.read(documentControllerProvider.notifier).flush();
      await settle();

      expect(test.changes.proposals, 0);
      expect(test.documents.commits, 0);
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[edited.id]
            ?.phase,
        DifferenceSyncPhase.savedLocally,
      );
    },
  );

  for (final role in [KbRole.editor, KbRole.coOwner]) {
    test('$role explicitly proposes and reuses the author proposal', () async {
      final test = await context(role: role);
      addTearDown(test.close);
      final controller = test.container.read(
        differencesControllerProvider.notifier,
      );

      final first = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'First reviewed edit')],
          ),
        ],
      );
      test.container.read(documentControllerProvider.notifier).edit(first);
      await controller.submitPendingEditNow(first.id);

      expect(test.changes.proposals, 1);
      expect(test.changes.latestContent?.plainText, 'First reviewed edit');
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[first.id]
            ?.phase,
        DifferenceSyncPhase.waitingForReview,
      );

      final second = first.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Continued reviewed edit')],
          ),
        ],
      );
      test.container.read(documentControllerProvider.notifier).edit(second);
      await controller.submitPendingEditNow(second.id);

      expect(test.changes.proposals, 2);
      expect(test.changes.latestContent?.plainText, 'Continued reviewed edit');
    });
  }

  for (final role in [KbRole.owner, KbRole.coOwner, KbRole.editor]) {
    test('$role explicitly publishes an unprotected document', () async {
      final test = await context(role: role);
      addTearDown(test.close);
      test.container.read(differencesControllerProvider);
      final edited = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Authoritative direct edit')],
          ),
        ],
      );
      test.container.read(documentControllerProvider.notifier).edit(edited);

      await test.container
          .read(sharingControllerProvider)
          .publishOpenDocument();

      expect(test.documents.commits, 1);
      expect(test.changes.withdrawals, 0);
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[edited.id]
            ?.phase,
        DifferenceSyncPhase.published,
      );
    });
  }

  for (final role in [KbRole.editor, KbRole.coOwner]) {
    test('$role proposes when Owner protection is required', () async {
      final test = await context(role: role);
      addTearDown(test.close);
      test.documents.currentProtection = const DocumentProtection(
        protectionClass: DocumentProtectionClass.protected,
        minimumPublishRole: MinimumPublishRole.owner,
      );
      final edited = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Protected local edit')],
          ),
        ],
      );
      test.container.read(documentControllerProvider.notifier).edit(edited);

      final result = await test.container
          .read(sharingControllerProvider)
          .publishOpenDocument();

      expect(result, SyncOutcome.proposed);
      expect(test.documents.commits, 0);
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[edited.id]
            ?.phase,
        DifferenceSyncPhase.waitingForReview,
      );
    });
  }

  test('a clean local copy applies a collaborator publish', () async {
    final test = await context(role: KbRole.editor);
    addTearDown(test.close);
    final remote = test.base.copyWith(
      blocks: const [
        ParagraphBlock(
          id: 'p-1',
          spans: [TextSpanNode(text: 'Published by collaborator')],
        ),
      ],
    );
    test.documents
      ..current = 'revision-2'
      ..currentDocument = remote;

    final result = await test.container
        .read(sharingControllerProvider)
        .pullRemoteChanges();

    expect(result.updated, 1);
    expect(
      (await test.kb.readDocument(test.path)).plainText,
      'Published by collaborator',
    );
    expect(
      (await SyncLedger.open(test.kb)).document(remote.id)?.revisionId,
      'revision-2',
    );
  });

  test(
    'a divergent local copy is preserved when a collaborator publishes',
    () async {
      final test = await context(role: KbRole.editor);
      addTearDown(test.close);
      test.container.read(differencesControllerProvider);
      final local = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Unpublished local words')],
          ),
        ],
      );
      test.container.read(documentControllerProvider.notifier).edit(local);
      await test.container.read(documentControllerProvider.notifier).flush();
      test.documents
        ..current = 'revision-2'
        ..currentDocument = test.base.copyWith(
          blocks: const [
            ParagraphBlock(
              id: 'p-1',
              spans: [TextSpanNode(text: 'Different remote words')],
            ),
          ],
        );

      final result = await test.container
          .read(sharingControllerProvider)
          .pullRemoteChanges();

      expect(result.conflicts, 1);
      expect(
        (await test.kb.readDocument(test.path)).plainText,
        'Unpublished local words',
      );
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[local.id]
            ?.phase,
        DifferenceSyncPhase.conflict,
      );
    },
  );

  test('non-overlapping simultaneous edits merge before publishing', () async {
    final test = await context(role: KbRole.editor);
    addTearDown(test.close);
    final local = test.base.copyWith(
      blocks: const [
        ParagraphBlock(
          id: 'p-1',
          spans: [TextSpanNode(text: 'Local paragraph edit')],
        ),
      ],
    );
    test.container.read(documentControllerProvider.notifier).edit(local);
    test.documents
      ..current = 'revision-2'
      ..currentDocument = test.base.copyWith(title: 'Remote title');

    final result = await test.container
        .read(sharingControllerProvider)
        .publishOpenDocument();

    expect(result, SyncOutcome.committed);
    expect(test.documents.commits, 1);
    expect(test.documents.currentDocument?.title, 'Remote title');
    expect(test.documents.currentDocument?.plainText, 'Local paragraph edit');
  });

  test('overlapping simultaneous edits stay local as a conflict', () async {
    final test = await context(role: KbRole.editor);
    addTearDown(test.close);
    final local = test.base.copyWith(
      blocks: const [
        ParagraphBlock(
          id: 'p-1',
          spans: [TextSpanNode(text: 'Local overlap')],
        ),
      ],
    );
    test.container.read(documentControllerProvider.notifier).edit(local);
    test.documents
      ..current = 'revision-2'
      ..currentDocument = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Remote overlap')],
          ),
        ],
      );

    await expectLater(
      test.container.read(sharingControllerProvider).publishOpenDocument(),
      throwsA(isA<PublishConflict>()),
    );

    expect(test.documents.commits, 0);
    expect((await test.kb.readDocument(test.path)).plainText, 'Local overlap');
  });

  test('switching documents does not strand a debounced proposal', () async {
    final test = await context();
    addTearDown(test.close);
    final controller = test.container.read(
      differencesControllerProvider.notifier,
    );
    final edited = test.base.copyWith(
      blocks: const [
        ParagraphBlock(
          id: 'p-1',
          spans: [TextSpanNode(text: 'Saved before switching documents')],
        ),
      ],
    );
    test.container.read(documentControllerProvider.notifier).edit(edited);

    final otherPath = await test.kb.createDocument(title: 'Other');
    await test.container
        .read(documentControllerProvider.notifier)
        .open(otherPath);
    await controller.submitPendingEditNow(edited.id);

    expect(test.changes.proposals, 1);
    expect(
      test.changes.latestContent?.plainText,
      'Saved before switching documents',
    );
  });

  test(
    'new files, renames, and deletes use their reviewed operations',
    () async {
      final test = await context();
      addTearDown(test.close);
      final controller = test.container.read(
        differencesControllerProvider.notifier,
      );
      await settle();

      test.container
          .read(documentControllerProvider.notifier)
          .relocate(test.path, 'Renamed.md', title: 'Renamed');
      final renamed = test.container.read(documentControllerProvider)!.document;
      await controller.submitPendingEditNow(renamed.id);
      expect(test.changes.latestPath, 'Renamed.md');

      final createdPath = await test.kb.createDocument(title: 'New Place');
      await test.container
          .read(documentControllerProvider.notifier)
          .open(createdPath);
      test.documents.current = null;
      final created = test.container
          .read(documentControllerProvider)!
          .document
          .copyWith(
            blocks: const [
              ParagraphBlock(
                id: 'new-p',
                spans: [TextSpanNode(text: 'A proposed new place')],
              ),
            ],
          );
      test.container.read(documentControllerProvider.notifier).edit(created);
      await controller.submitPendingEditNow(created.id);
      expect(test.changes.creates, 1);

      test.documents.current = 'base-1';
      await test.container
          .read(documentControllerProvider.notifier)
          .open(test.path);
      await test.container
          .read(sharingControllerProvider)
          .syncDeletion(test.path);
      expect(test.documents.deletions, 1);
    },
  );

  test('reviewers remain unable to publish or submit edits', () async {
    final test = await context(role: KbRole.reviewer);
    addTearDown(test.close);
    final controller = test.container.read(
      differencesControllerProvider.notifier,
    );
    await settle();
    final edited = test.base.copyWith(
      blocks: const [
        ParagraphBlock(
          id: 'p-1',
          spans: [TextSpanNode(text: 'Reviewer attempted edit')],
        ),
      ],
    );
    test.container.read(documentControllerProvider.notifier).edit(edited);
    await controller.submitPendingEditNow(edited.id);
    expect(test.changes.proposals, 0);
    await expectLater(
      test.container
          .read(sharingControllerProvider)
          .publishOpenDocumentDirectly(),
      throwsA(isA<Exception>()),
    );
  });

  test(
    'queue keeps multiple authors for one document and hides own proposal',
    () async {
      final test = await context();
      addTearDown(test.close);
      test.changes.pending = [
        change(id: 'alice', authorId: 'alice', username: 'alice'),
        change(id: 'bob', authorId: 'bob', username: 'bob'),
        change(id: 'mine', authorId: user.id, username: 'local-author'),
      ];
      final controller = test.container.read(
        differencesControllerProvider.notifier,
      );
      await settle();
      await controller.refresh(showLoading: true);
      await settle();

      final state = test.container.read(differencesControllerProvider);
      expect(state.proposals.map((item) => item.id), ['alice', 'bob']);
      expect(controller.forDocument('doc-1'), hasLength(2));
    },
  );

  test(
    'PostgREST errors stay visible instead of becoming an empty queue',
    () async {
      final test = await context();
      addTearDown(test.close);
      test.changes.pendingError = const PostgrestException(
        message: 'profile relationship is invalid',
        code: 'PGRST200',
      );
      final controller = test.container.read(
        differencesControllerProvider.notifier,
      );
      await settle();
      await controller.refresh(showLoading: true);
      await settle();

      final state = test.container.read(differencesControllerProvider);
      expect(state.status, DifferencesLoadStatus.error);
      expect(state.errorMessage, contains('PGRST200'));
    },
  );

  test(
    'focus refresh recovers the durable queue after Realtime/network failure',
    () async {
      final test = await context();
      addTearDown(test.close);
      test.changes.pendingError = const SocketException('offline');
      final controller = test.container.read(
        differencesControllerProvider.notifier,
      );
      await settle();
      await controller.refresh(showLoading: true);
      await settle();
      expect(
        test.container.read(differencesControllerProvider).status,
        DifferencesLoadStatus.offline,
      );

      test.changes
        ..pendingError = null
        ..pending = [change(id: 'recovered', authorId: 'alice')];
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await settle();

      final recovered = test.container.read(differencesControllerProvider);
      expect(recovered.status, DifferencesLoadStatus.ready);
      expect(recovered.proposals.single.id, 'recovered');
    },
  );

  test(
    'focus does not transmit an offline local edit without Publish',
    () async {
      final test = await context();
      addTearDown(test.close);
      final controller = test.container.read(
        differencesControllerProvider.notifier,
      );
      test.changes.proposalError = const SocketException('offline');
      final edited = test.base.copyWith(
        blocks: const [
          ParagraphBlock(
            id: 'p-1',
            spans: [TextSpanNode(text: 'Retry this proposal')],
          ),
        ],
      );
      test.container.read(documentControllerProvider.notifier).edit(edited);
      await controller.submitPendingEditNow(edited.id);
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[edited.id]
            ?.phase,
        DifferenceSyncPhase.offline,
      );

      test.changes.proposalError = null;
      controller.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(test.changes.proposals, 0);
      await controller.submitPendingEditNow(edited.id);
      expect(test.changes.proposals, 1);
      expect(
        test.container
            .read(differencesControllerProvider)
            .documentSync[edited.id]
            ?.phase,
        DifferenceSyncPhase.waitingForReview,
      );
    },
  );
}
