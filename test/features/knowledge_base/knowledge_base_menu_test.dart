import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/sharing.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/features/knowledge_base/ui/knowledge_base_menu.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

User _signedInUser() => User(
  id: '466839ae-d51e-4e44-a8cb-a4d966f14918',
  appMetadata: const {},
  userMetadata: const {'username': 'owner', 'display_name': 'Owner'},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026, 8, 20).toIso8601String(),
);

class _DocumentRepositoryStub extends DocumentRepository {
  _DocumentRepositoryStub(this.rows);

  final List<Map<String, Object?>> rows;

  @override
  Future<List<Map<String, Object?>>> documentsIn(String kbId) async => rows;
}

class _SyncAssetRepository extends AssetRepository {
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

class _SyncDocumentRepository extends DocumentRepository {
  _SyncDocumentRepository({
    this.snapshots = const [],
    this.snapshotError,
    this.proposeChanges = false,
  });

  List<RemoteDocumentSnapshot> snapshots;
  final Object? snapshotError;
  final bool proposeChanges;
  int publishCalls = 0;

  @override
  Future<List<RemoteDocumentSnapshot>> snapshot(String kbId) async {
    final error = snapshotError;
    if (error != null) throw error;
    return snapshots;
  }

  @override
  Future<DocumentPublishReceipt> publishChange({
    required String kbId,
    required String relativePath,
    required BlockDocument document,
    required String? expectedCurrentRevisionId,
  }) async {
    publishCalls++;
    if (proposeChanges) {
      return DocumentPublishReceipt.proposed('proposal-$publishCalls');
    }
    final published = RemoteDocumentSnapshot(
      path: relativePath,
      revisionId: 'published-$publishCalls',
      document: document,
    );
    snapshots = [
      ...snapshots.where((item) => item.document.id != document.id),
      published,
    ];
    return DocumentPublishReceipt.published(published.revisionId);
  }

  @override
  Future<List<Map<String, Object?>>> documentsIn(String kbId) async => const [];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;
  late Directory support;
  late ProviderContainer container;
  late KnowledgeBase kb;
  late String originalPath;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('dayseven_rename_test');
    support = await Directory.systemTemp.createTemp('dayseven_rename_support');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => call.method == 'getApplicationSupportDirectory'
              ? support.path
              : null,
        );

    kb = await KnowledgeBase.create(folder: temp.path, name: 'MyWorld');
    originalPath = await kb.createDocument(title: 'Aldric');
    container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(_signedInUser()),
        kbRoleProvider.overrideWith((ref) async => KbRole.local),
        recentKbPathsProvider.overrideWith((ref) async => const []),
      ],
    );
    await container.read(kbControllerProvider.notifier).openFolder(temp.path);
    await container
        .read(documentControllerProvider.notifier)
        .open(originalPath);
  });

  tearDown(() async {
    container.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
    if (await temp.exists()) await temp.delete(recursive: true);
    if (await support.exists()) await support.delete(recursive: true);
  });

  Future<_SyncDocumentRepository> useSharedRole(
    KbRole role, {
    List<RemoteDocumentSnapshot> snapshots = const [],
    Object? snapshotError,
    bool proposeChanges = false,
  }) async {
    container.dispose();
    final documents = _SyncDocumentRepository(
      snapshots: snapshots,
      snapshotError: snapshotError,
      proposeChanges: proposeChanges,
    );
    container = ProviderContainer(
      overrides: [
        currentUserProvider.overrideWithValue(_signedInUser()),
        kbRoleProvider.overrideWith((ref) async => role),
        recentKbPathsProvider.overrideWith((ref) async => const []),
        documentRepositoryProvider.overrideWithValue(documents),
        assetRepositoryProvider.overrideWithValue(_SyncAssetRepository()),
      ],
    );
    await container.read(kbControllerProvider.notifier).openFolder(temp.path);
    return documents;
  }

  Future<void> pumpMenu(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> runSync(WidgetTester tester) async {
    final button = tester.widget<DsButton>(
      find.byKey(const Key('knowledge-base-sync-button')),
    );
    expect(button.onPressed, isNotNull);
    await tester.runAsync(() async {
      final dynamic invoke = button.onPressed!;
      await invoke();
    });
    await tester.pumpAndSettle();
  }

  testWidgets('shows a transparent header above folder and hierarchy islands', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final header = tester.widget<Text>(find.text('Knowledge Base'));
    expect(header.style?.fontFamily, kUiHeaderFontFamily);
    final hierarchyItem = tester.widget<Text>(find.text('Aldric'));
    expect(hierarchyItem.style?.fontFamily, kDefaultFontFamily);
    expect(
      find.ancestor(
        of: find.text('Knowledge Base'),
        matching: find.byType(DsIsland),
      ),
      findsNothing,
    );
    expect(find.text('MyWorld'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Knowledge Base')).dy,
      lessThan(tester.getTopLeft(find.text('MyWorld')).dy),
    );
    expect(
      tester.getTopLeft(find.text('MyWorld')).dy,
      lessThan(tester.getTopLeft(find.text('Aldric')).dy),
    );

    final access = tester.getRect(
      find.byKey(const Key('knowledge-base-access-controls')),
    );
    final hierarchy = tester.getRect(
      find.byKey(const Key('knowledge-base-hierarchy')),
    );
    final active = tester.getRect(
      find.byKey(const Key('active-knowledge-base-button')),
    );
    final settings = tester.getRect(
      find.byKey(const Key('knowledge-base-settings-button')),
    );
    final sync = tester.getRect(
      find.byKey(const Key('knowledge-base-sync-button')),
    );
    expect(access.left, hierarchy.left);
    expect(access.right, hierarchy.right);
    expect(active.width, lessThan(hierarchy.width));
    expect(active.right, lessThan(sync.left));
    expect(sync.right, lessThan(settings.left));
    expect(active.height, settings.height);
    expect(sync.height, settings.height);
    expect(find.byTooltip('Sync Knowledge Base'), findsOneWidget);
    expect(find.byIcon(Icons.sync), findsOneWidget);
    expect(
      tester
          .widget<DsButton>(find.byKey(const Key('knowledge-base-sync-button')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('Sync pulls first and publishes local changes for an owner', (
    tester,
  ) async {
    final documents = (await tester.runAsync(
      () => useSharedRole(KbRole.owner),
    ))!;
    await pumpMenu(tester);

    await runSync(tester);

    expect(documents.publishCalls, 1);
    final notification = container.read(notificationStoreProvider).single;
    expect(notification.kind, DsNotificationKind.sync);
    expect(notification.message, '0 pulled · 1 published');
    expect(
      tester
          .widget<DsButton>(find.byKey(const Key('knowledge-base-sync-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('Sync only pulls canonical changes for a reviewer', (
    tester,
  ) async {
    final remote = BlockDocument(
      id: 'remote-lore',
      title: 'Lore',
      blocks: const [
        ParagraphBlock(
          id: 'lore-body',
          spans: [TextSpanNode(text: 'Canonical lore.')],
        ),
      ],
    );
    final documents = (await tester.runAsync(
      () => useSharedRole(
        KbRole.reviewer,
        snapshots: [
          RemoteDocumentSnapshot(
            path: 'Lore.md',
            revisionId: 'remote-1',
            document: remote,
          ),
        ],
      ),
    ))!;
    await pumpMenu(tester);

    await runSync(tester);

    expect(documents.publishCalls, 0);
    expect(File(kb.absolutePathFor('Lore.md')).existsSync(), isTrue);
    final notification = container.read(notificationStoreProvider).single;
    expect(notification.kind, DsNotificationKind.sync);
    expect(notification.message, '1 pulled');
  });

  testWidgets('Sync submits an editor local change for review', (tester) async {
    final documents = (await tester.runAsync(
      () => useSharedRole(KbRole.editor, proposeChanges: true),
    ))!;
    await pumpMenu(tester);

    await runSync(tester);

    expect(documents.publishCalls, 1);
    final notification = container.read(notificationStoreProvider).single;
    expect(notification.kind, DsNotificationKind.sync);
    expect(notification.message, '0 pulled · 0 published · 1 proposed');
  });

  testWidgets('a failed Sync reports the error and re-enables the button', (
    tester,
  ) async {
    await tester.runAsync(
      () => useSharedRole(
        KbRole.owner,
        snapshotError: const SyncException('Network unavailable.'),
      ),
    );
    await pumpMenu(tester);

    await runSync(tester);

    final notification = container.read(notificationStoreProvider).single;
    expect(notification.kind, DsNotificationKind.error);
    expect(notification.message, 'Network unavailable.');
    expect(
      tester
          .widget<DsButton>(find.byKey(const Key('knowledge-base-sync-button')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('marks protected documents with a shield in the hierarchy', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final document = await kb.readDocument(originalPath);
      final ledger = await SyncLedger.open(kb);
      await ledger.record(
        document: document,
        revisionId: 'protected-revision',
        path: originalPath,
        protection: const DocumentProtection(
          protectionClass: DocumentProtectionClass.protected,
          minimumPublishRole: MinimumPublishRole.owner,
        ),
      );
      container.invalidate(protectedDocumentsByPathProvider);
      await container.read(protectedDocumentsByPathProvider.future);
    });

    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('protected-document-$originalPath')),
      findsOneWidget,
    );
    expect(find.byTooltip('Protected · Owner required'), findsOneWidget);
  });

  testWidgets('shows every protected document returned by canonical metadata', (
    tester,
  ) async {
    late String secondPath;
    late String firstId;
    late String secondId;
    await tester.runAsync(() async {
      secondPath = await kb.createDocument(title: 'Kuras');
      firstId = (await kb.readDocument(originalPath)).id;
      secondId = (await kb.readDocument(secondPath)).id;

      container.dispose();
      container = ProviderContainer(
        overrides: [
          currentUserProvider.overrideWithValue(_signedInUser()),
          kbRoleProvider.overrideWith((ref) async => KbRole.owner),
          recentKbPathsProvider.overrideWith((ref) async => const []),
          documentRepositoryProvider.overrideWithValue(
            _DocumentRepositoryStub([
              {
                'id': firstId,
                'path': originalPath,
                'protection_class': 'protected',
                'minimum_publish_role': 'owner',
              },
              {
                'id': secondId,
                'path': secondPath,
                'protection_class': 'protected',
                'minimum_publish_role': 'co_owner',
              },
            ]),
          ),
        ],
      );
      await container.read(kbControllerProvider.notifier).openFolder(temp.path);
      await container.read(protectedDocumentsByPathProvider.future);
    });

    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(ValueKey('protected-document-$originalPath')),
      findsOneWidget,
    );
    expect(
      find.byKey(ValueKey('protected-document-$secondPath')),
      findsOneWidget,
    );
  });

  testWidgets('invites the user to open a folder when no base is active', (
    tester,
  ) async {
    final emptyContainer = ProviderContainer();
    addTearDown(emptyContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: emptyContainer,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(
            body: SizedBox(width: 300, height: 600, child: KnowledgeBaseMenu()),
          ),
        ),
      ),
    );

    expect(find.text('Knowledge Base'), findsOneWidget);
    expect(find.text('Open a folder…'), findsOneWidget);
    expect(find.byTooltip('Sync Knowledge Base'), findsNothing);
    expect(find.byTooltip('Knowledge Base settings'), findsNothing);
    expect(find.byType(DsIsland), findsNothing);
  });

  testWidgets(
    'settings owns sharing and explains that remote deletion preserves files',
    (tester) async {
      tester.view.physicalSize = const Size(500, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dsTheme(),
            home: const Scaffold(body: KnowledgeBaseMenu()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Knowledge Base settings'));
      await tester.pumpAndSettle();

      expect(find.text('Knowledge Base Settings'), findsOneWidget);
      expect(find.text('Share Knowledge Base'), findsOneWidget);
      expect(find.text('Delete Shared Knowledge Base'), findsOneWidget);
      expect(
        find.textContaining('on-disk Knowledge Base is not deleted or changed'),
        findsOneWidget,
      );

      final danger = tester.widget<Text>(
        find.text('Delete Shared Knowledge Base'),
      );
      expect(
        danger.style?.color,
        Theme.of(tester.element(find.text('Delete Shared Knowledge Base')))
            .colorScheme
            .error,
      );

      await tester.tap(
        find.byKey(const Key('delete-shared-knowledge-base-setting')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Delete shared Knowledge Base?'), findsOneWidget);
      expect(
        find.textContaining(
          'does not delete or change the Knowledge Base folder',
        ),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextButton, 'Delete Shared Knowledge Base'),
        findsWidgets,
      );

      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();
      expect(Directory(temp.path).existsSync(), isTrue);
      expect(File(kb.absolutePathFor(originalPath)).existsSync(), isTrue);
    },
  );

  testWidgets(
    'right-click creates at the root or inside folders, never inside files',
    (tester) async {
      await tester.runAsync(
        () => container
            .read(kbControllerProvider.notifier)
            .createFolder(name: 'Characters'),
      );

      tester.view.physicalSize = const Size(500, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: dsTheme(),
            home: const Scaffold(body: KnowledgeBaseMenu()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Creation no longer competes with folder access in the KB dropdown.
      await tester.tap(find.byKey(const Key('active-knowledge-base-button')));
      await tester.pumpAndSettle();
      expect(find.text('Import .docx or .odt…'), findsOneWidget);
      expect(find.text('New document'), findsNothing);
      expect(find.text('New folder…'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // Blank hierarchy space represents the Knowledge Base root.
      final hierarchy = tester.getRect(
        find.byKey(const Key('knowledge-base-root-context-target')),
      );
      await tester.tapAt(
        Offset(hierarchy.center.dx, hierarchy.bottom - 16),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('New file'), findsOneWidget);
      expect(find.text('New folder…'), findsOneWidget);

      await tester.tap(find.text('New folder…'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextButton, 'Create'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Folder-row creation is explicitly scoped to that folder.
      await tester.tap(
        find.text('Characters'),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('New file here'), findsOneWidget);
      expect(find.text('New folder here…'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      // A file cannot be used as a parent.
      await tester.tap(
        find.text('Aldric'),
        buttons: kSecondaryMouseButton,
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(find.text('Rename…'), findsOneWidget);
      expect(find.text('Delete…'), findsOneWidget);
      expect(find.text('New file'), findsNothing);
      expect(find.text('New file here'), findsNothing);
      expect(find.text('New folder…'), findsNothing);
      expect(find.text('New folder here…'), findsNothing);
    },
  );

  testWidgets('folder plus creates and opens an Untitled file inside it', (
    tester,
  ) async {
    await tester.runAsync(
      () => container
          .read(kbControllerProvider.notifier)
          .createFolder(name: 'Characters'),
    );

    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final add = find.byKey(const ValueKey('new-file-in-Characters'));
    expect(add, findsOneWidget);
    expect(find.byTooltip('New file in Characters'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.byKey(ValueKey('new-file-in-$originalPath')), findsNothing);

    final button = tester.widget<IconButton>(add);
    expect(button.onPressed, isNotNull);
    await tester.runAsync(() async {
      // Run the button's real callback in the real-async zone. Widget tests
      // cannot resume file-I/O futures launched by an unawaited synthetic tap
      // once that tap has returned to the fake clock.
      button.onPressed!();
      final created = File(kb.absolutePathFor('Characters/Untitled.md'));
      for (var attempt = 0; attempt < 400 && !created.existsSync(); attempt++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      for (
        var attempt = 0;
        attempt < 400 &&
            container.read(documentControllerProvider)?.relativePath !=
                'Characters/Untitled.md';
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();

    expect(
      File(kb.absolutePathFor('Characters/Untitled.md')).existsSync(),
      isTrue,
    );
    expect(find.text('Untitled'), findsOneWidget);
    expect(
      container.read(documentControllerProvider)?.relativePath,
      'Characters/Untitled.md',
    );
  });

  testWidgets('right-click exposes rename and the workspace renames the file', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Aldric'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    expect(find.text('Rename…'), findsOneWidget);
    expect(find.text('Delete…'), findsOneWidget);

    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextButton, 'Rename'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'The Gatekeeper.md');
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller?.text, 'The Gatekeeper.md');

    // Close the dialog before crossing into real filesystem async. Widget
    // tests cannot advance file-I/O futures started by an unawaited gesture
    // callback in their fake clock; the command the button calls is exercised
    // directly below.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    const renamedPath = 'The Gatekeeper.md';
    await tester.runAsync(
      () => container
          .read(kbControllerProvider.notifier)
          .renameDocument(originalPath, renamedPath),
    );
    await tester.pumpAndSettle();

    expect(File(kb.absolutePathFor(originalPath)).existsSync(), isFalse);
    expect(find.text('The Gatekeeper'), findsOneWidget);
    expect(
      container.read(documentControllerProvider)?.relativePath,
      renamedPath,
    );
    final renamedDocument = await tester.runAsync(
      () => kb.readDocument(renamedPath),
    );
    expect(renamedDocument?.title, 'The Gatekeeper');

    final index = container.read(kbSessionProvider)!.index;
    expect(index.search('Aldric'), isEmpty);
    expect(index.search('Gatekeeper').single.relativePath, renamedPath);
  });

  testWidgets('the first folder has extra breathing room above it', (
    tester,
  ) async {
    await tester.runAsync(
      () => container
          .read(kbControllerProvider.notifier)
          .createFolder(name: 'Characters'),
    );

    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Characters'), findsOneWidget);
    final tree = tester.widget<ListView>(find.byKey(const Key('kb-tree-list')));
    expect(tree.padding, const EdgeInsets.fromLTRB(0, 12, 0, 4));
  });

  testWidgets('right-click delete confirms before removing the document', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(500, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(body: KnowledgeBaseMenu()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.text('Aldric'),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();

    expect(find.text('Delete “Aldric”?'), findsOneWidget);
    expect(find.textContaining('This cannot be undone.'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Delete'), findsOneWidget);

    // Cancelling leaves the document untouched.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(File(kb.absolutePathFor(originalPath)).existsSync(), isTrue);

    // Exercise the confirmed command with real filesystem async.
    await tester.runAsync(
      () => container
          .read(kbControllerProvider.notifier)
          .deleteNode(originalPath),
    );
    await tester.pumpAndSettle();

    expect(File(kb.absolutePathFor(originalPath)).existsSync(), isFalse);
    expect(container.read(documentControllerProvider), isNull);
    expect(find.text('Aldric'), findsNothing);
    expect(
      find.text('No files or folders yet. Right-click to create one.'),
      findsOneWidget,
    );
    expect(container.read(kbSessionProvider)!.index.search('Aldric'), isEmpty);

    final recent = await tester.runAsync(() async {
      final store = await container.read(appStoreProvider.future);
      return store.recentDocuments(kb.manifest.kbId);
    });
    expect(recent, isEmpty);
  });
}
