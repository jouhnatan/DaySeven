/// Presence chrome: the dots in the tree and the marker beside a block.
///
/// The controller itself needs a live socket, so what is checked here is
/// everything downstream of it — that a peer's position lands on the right
/// row and the right block, and that a peer whose block this copy does not
/// have degrades to a document-level indicator rather than a wrong marker.
library;

import 'dart:io';

import 'package:dayseven/app/workspace/document_presence_indicator.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/presence.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/presence/peer_presence.dart';
import 'package:dayseven/shared/ui/presence_dots.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

PeerPresence _peer(
  String userId, {
  String? path,
  String? blockId,
  bool idle = false,
}) => PeerPresence(
  userId: userId,
  username: userId,
  displayName: '${userId[0].toUpperCase()}${userId.substring(1)}',
  relativePath: path,
  documentId: path == null ? null : 'doc-$path',
  blockId: blockId,
  idle: idle,
  updatedAt: DateTime.utc(2026, 8, 25, 12),
);

final _seed = BlockDocument(
  id: 'doc-1',
  title: 'Aldenmoor',
  blocks: const [
    ParagraphBlock(
      id: 'p1',
      spans: [TextSpanNode(text: 'The moor is wide.')],
    ),
    ParagraphBlock(
      id: 'p2',
      spans: [TextSpanNode(text: 'And it is cold.')],
    ),
  ],
);

Future<Widget> _wrap(Widget child, {Brightness brightness = Brightness.dark}) =>
    Future.value(
      MaterialApp(
        theme: dsTheme(brightness),
        home: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PresenceDots', () {
    testWidgets('renders nothing when nobody is there', (tester) async {
      await tester.pumpWidget(await _wrap(const PresenceDots(peers: [])));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('caps the stack and counts the rest', (tester) async {
      await tester.pumpWidget(
        await _wrap(
          PresenceDots(
            peers: [
              _peer('alice'),
              _peer('bru'),
              _peer('cyd'),
              _peer('dag'),
              _peer('eun'),
            ],
          ),
        ),
      );
      expect(find.text('A'), findsOneWidget);
      expect(find.text('B'), findsOneWidget);
      expect(find.text('C'), findsOneWidget);
      expect(find.text('D'), findsNothing);
      expect(find.text('+2'), findsOneWidget);
    });

    testWidgets('names everyone in a sentence', (tester) async {
      await tester.pumpWidget(
        await _wrap(
          PresenceDots(peers: [_peer('alice'), _peer('bru', idle: true)]),
        ),
      );
      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Alice and Bru (idle) are here');
    });

    testWidgets('gives a peer the same colour every time', (tester) async {
      final first = presenceColorFor('466839ae-d51e-4e44-a8cb-a4d966f14918');
      expect(presenceColorFor('466839ae-d51e-4e44-a8cb-a4d966f14918'), first);
      expect(DsPresence.palette, contains(first));
    });
  });

  group('in the editor', () {
    late Directory temp;
    late Directory support;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('dayseven_presence');
      support = await Directory.systemTemp.createTemp('dayseven_presence_sup');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationSupportDirectory'
                ? support.path
                : null,
          );
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            null,
          );
      if (await temp.exists()) await temp.delete(recursive: true);
      if (await support.exists()) await support.delete(recursive: true);
    });

    Future<ProviderContainer> openWith(
      WidgetTester tester,
      List<PeerPresence> peers,
    ) async {
      late String path;
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await tester.runAsync(() async {
        await container
            .read(kbControllerProvider.notifier)
            .openFolder(temp.path, createWithName: 'MyWorld');
        final session = container.read(kbSessionProvider)!;
        path = await session.kb.createDocument(title: 'Aldenmoor');
        await session.kb.writeDocument(path, _seed);
        await container.read(kbControllerProvider.notifier).refreshTree();
        await container.read(documentControllerProvider.notifier).open(path);
      });

      // The controller needs a socket, so the providers it feeds stand in for
      // it. Everything under test is downstream of exactly this map.
      final located = [
        for (final peer in peers)
          peer.relativePath == null
              ? peer.copyWith(relativePath: () => path)
              : peer,
      ];

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [
              peersByPathProvider.overrideWithValue(peersByPath(located)),
              peersByBlockProvider.overrideWithValue(
                peersByBlock(
                  located,
                  relativePath: path,
                  knownBlockIds: {'p1', 'p2'},
                ),
              ),
              peersInOpenDocumentProvider.overrideWithValue(located),
            ],
            child: MaterialApp(
              theme: dsTheme(Brightness.dark),
              home: const Scaffold(
                body: Column(
                  children: [
                    Expanded(child: EditorScreen()),
                    DocumentPresenceIndicator(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('marks the block a collaborator is in', (tester) async {
      await openWith(tester, [_peer('alice', blockId: 'p2')]);
      expect(
        find.byKey(const ValueKey('presence-in-block-p2')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('presence-in-block-p1')), findsNothing);
    });

    testWidgets('marks no block when nobody is in one', (tester) async {
      await openWith(tester, const []);
      expect(find.byKey(const ValueKey('presence-in-block-p1')), findsNothing);
      expect(find.byKey(const ValueKey('presence-in-block-p2')), findsNothing);
      expect(find.byKey(const Key('document-presence')), findsNothing);
    });

    testWidgets(
      'a peer on a block this copy lacks still shows in the bottom bar',
      (tester) async {
        // Their proposal has not been approved here, so `theirs` does not
        // exist in this copy of the document. Drawing a marker against some
        // other block would be a guess; saying nothing at all would lose them.
        await openWith(tester, [_peer('alice', blockId: 'theirs')]);
        expect(
          find.byKey(const ValueKey('presence-in-block-theirs')),
          findsNothing,
        );
        expect(find.byKey(const Key('document-presence')), findsOneWidget);
        expect(find.text('A'), findsOneWidget);
      },
    );
  });
}
