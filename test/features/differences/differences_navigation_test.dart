import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/application/differences_navigation.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/features/differences/ui/review_edits_screen.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ChangeSet item(String id, String documentId, String username) => ChangeSet(
  id: id,
  kbId: 'kb',
  documentId: null,
  targetDocumentId: documentId,
  baseRevisionId: null,
  content: BlockDocument(
    id: documentId,
    title: 'Document $documentId',
    blocks: const [],
  ),
  authorId: 'author-$username',
  authorUsername: username,
  authorDisplayName: username,
  status: ChangeSetStatus.pending,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
  operation: ChangeSetOperation.create,
  proposedPath: '$documentId.md',
);

Widget harness(List<ChangeSet> proposals, String documentId) => ProviderScope(
  overrides: [
    differencesStateProvider.overrideWithValue(
      DifferencesState(
        proposals: proposals,
        status: DifferencesLoadStatus.ready,
      ),
    ),
  ],
  child: MaterialApp(
    theme: dsTheme(),
    home: Consumer(
      builder: (context, ref, _) => Scaffold(
        body: TextButton(
          onPressed: () => openDifferencesForDocument(context, ref, documentId),
          child: const Text('Open contextual Differences'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('contextual shortcut opens only the current document proposal', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([
        item('a', 'doc-a', 'alice'),
        item('b', 'doc-b', 'bob'),
      ], 'doc-b'),
    );
    await tester.tap(find.text('Open contextual Differences'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewEditsScreen), findsOneWidget);
    expect(find.text('proposed by @bob'), findsOneWidget);
    expect(find.text('1 of 1'), findsOneWidget);
    expect(find.text('proposed by @alice'), findsNothing);
  });

  testWidgets('multiple proposals for one document share previous/next flow', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([
        item('a', 'doc-a', 'alice'),
        item('b', 'doc-a', 'bob'),
      ], 'doc-a'),
    );
    await tester.tap(find.text('Open contextual Differences'));
    await tester.pumpAndSettle();

    expect(find.text('1 of 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('review-next-proposal')));
    await tester.pumpAndSettle();
    expect(find.text('proposed by @bob'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
  });
}
