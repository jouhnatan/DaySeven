import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/features/differences/ui/differences_workspace.dart';
import 'package:dayseven/features/differences/ui/review_edits_screen.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ChangeSet proposal({
  required String id,
  String documentId = 'doc-1',
  String username = 'horido',
  String title = 'Aldenmoor',
  String words = 'Fog sits low over the eastern fen.',
}) => ChangeSet(
  id: id,
  kbId: 'kb-1',
  documentId: null,
  targetDocumentId: documentId,
  baseRevisionId: null,
  content: BlockDocument(
    id: documentId,
    title: title,
    blocks: [
      HeadingBlock(
        id: 'heading-$id',
        level: 2,
        spans: [TextSpanNode(text: 'The Eastern Fen')],
      ),
      ParagraphBlock(
        id: 'paragraph-$id',
        spans: [TextSpanNode(text: words, bold: true)],
      ),
    ],
  ),
  authorId: 'author-$username',
  authorUsername: username,
  authorDisplayName: 'Display $username',
  status: ChangeSetStatus.pending,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
  operation: ChangeSetOperation.create,
  proposedPath: '$title.md',
);

Widget harness(List<ChangeSet> proposals) => ProviderScope(
  overrides: [
    differencesStateProvider.overrideWithValue(
      DifferencesState(
        proposals: proposals,
        status: proposals.isEmpty
            ? DifferencesLoadStatus.empty
            : DifferencesLoadStatus.ready,
        realtimeHealth: DifferencesRealtimeHealth.connected,
      ),
    ),
  ],
  child: MaterialApp(
    theme: dsTheme(),
    home: const Scaffold(body: DifferencesWorkspace()),
  ),
);

void main() {
  testWidgets('paper preview renders document words and @username band', (
    tester,
  ) async {
    await tester.pumpWidget(harness([proposal(id: 'proposal-1')]));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('differences-paper-grid')), findsOneWidget);
    expect(find.text('The Eastern Fen'), findsOneWidget);
    expect(find.text('Fog sits low over the eastern fen.'), findsOneWidget);
    expect(find.text('@horido'), findsOneWidget);
    expect(
      find.byKey(const Key('proposal-author-band-proposal-1')),
      findsOneWidget,
    );
    expect(
      find.ancestor(
        of: find.text('Fog sits low over the eastern fen.'),
        matching: find.byType(IgnorePointer),
      ),
      findsWidgets,
    );
    expect(find.byIcon(Icons.insert_drive_file), findsNothing);
  });

  testWidgets('clicking a paper opens Review edits for that proposal', (
    tester,
  ) async {
    final second = proposal(
      id: 'proposal-2',
      documentId: 'doc-2',
      username: 'mira',
      title: 'North Gate',
      words: 'The gate opens at dawn.',
    );
    await tester.pumpWidget(harness([proposal(id: 'proposal-1'), second]));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proposal-paper-proposal-2')));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewEditsScreen), findsOneWidget);
    expect(find.text('Review edits'), findsOneWidget);
    expect(find.text('proposed by @mira'), findsOneWidget);
    expect(find.text('2 of 2'), findsOneWidget);
  });

  testWidgets('multiple collaborators get separate papers for one document', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness([
        proposal(id: 'proposal-a', username: 'alice'),
        proposal(id: 'proposal-b', username: 'bob'),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('@bob'), findsOneWidget);
    expect(find.byType(ProposalPaperCard), findsNWidgets(2));
  });

  testWidgets('large queues are lazy and scrollable', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final proposals = [
      for (var i = 0; i < 250; i++)
        proposal(id: 'proposal-$i', documentId: 'doc-$i', title: 'Doc $i'),
    ];
    await tester.pumpWidget(harness(proposals));
    await tester.pumpAndSettle();

    expect(find.byType(ProposalPaperCard), findsWidgets);
    expect(find.byKey(const Key('proposal-paper-proposal-249')), findsNothing);
    expect(find.byType(ProposalPaperCard).evaluate().length, lessThan(20));
  });
}
