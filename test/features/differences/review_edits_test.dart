import 'package:dayseven/features/differences/data/change_set_repository.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/features/differences/ui/review_edits_screen.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

ChangeSet proposal() => ChangeSet(
  id: 'proposal-1',
  kbId: 'kb-1',
  documentId: null,
  targetDocumentId: 'doc-1',
  baseRevisionId: null,
  content: const BlockDocument(
    id: 'doc-1',
    title: 'New Chronicle',
    blocks: [
      ParagraphBlock(
        id: 'p-1',
        spans: [TextSpanNode(text: 'Proposed canonical words')],
      ),
    ],
  ),
  authorId: 'author-1',
  authorUsername: 'horido',
  authorDisplayName: 'Horido',
  status: ChangeSetStatus.pending,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
  operation: ChangeSetOperation.create,
  proposedPath: 'New Chronicle.md',
);

class ReviewRepository implements ChangeSetDataSource {
  int approvals = 0;
  int rejections = 0;
  String? note;
  Object? approvalError;

  @override
  Future<String?> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
    String? reviewNote,
  }) async {
    approvals++;
    note = reviewNote;
    final error = approvalError;
    if (error != null) {
      approvalError = null;
      throw error;
    }
    return 'revision-1';
  }

  @override
  Future<void> reject(String changeSetId, {String? reviewNote}) async {
    rejections++;
    note = reviewNote;
  }

  @override
  Future<ChangeSet?> byId(String changeSetId) async => proposal();

  @override
  Future<List<ChangeSet>> pendingForKb(String kbId) async => [proposal()];

  @override
  Future<ChangeSet> propose({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    String? relativePath,
    required BlockDocument content,
  }) => throw UnimplementedError();

  @override
  Future<ChangeSet> proposeCreate({
    required String kbId,
    required String relativePath,
    required BlockDocument content,
  }) => throw UnimplementedError();

  @override
  Future<ChangeSet> proposeDelete({
    required String kbId,
    required String documentId,
    required String baseRevisionId,
    required String relativePath,
  }) => throw UnimplementedError();

  @override
  Future<void> withdrawForDocument({
    required String kbId,
    required String documentId,
  }) async {}
}

Widget harness(ReviewRepository repository) => ProviderScope(
  overrides: [changeSetRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    theme: dsTheme(Brightness.dark),
    home: ReviewEditsScreen(
      proposals: [proposal()],
      initialProposalId: 'proposal-1',
    ),
  ),
);

void main() {
  testWidgets('approve creates one revision and forwards review notes', (
    tester,
  ) async {
    final repository = ReviewRepository();
    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Looks good.');
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(repository.approvals, 1);
    expect(repository.rejections, 0);
    expect(repository.note, 'Looks good.');
  });

  testWidgets('reject never invokes canonical approval', (tester) async {
    final repository = ReviewRepository();
    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Needs another pass.');
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(repository.approvals, 0);
    expect(repository.rejections, 1);
    expect(repository.note, 'Needs another pass.');
  });

  testWidgets('stale optimistic lock is visible and recomputes review', (
    tester,
  ) async {
    final repository = ReviewRepository()
      ..approvalError = const PostgrestException(
        message: 'document moved on',
        code: '40001',
      );
    await tester.pumpWidget(harness(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(find.byType(ReviewEditsScreen), findsOneWidget);
    expect(find.textContaining('canonical revision changed'), findsOneWidget);
    expect(repository.approvals, 1);
  });
}
