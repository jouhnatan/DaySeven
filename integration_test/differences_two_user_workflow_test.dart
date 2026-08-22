import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/data/change_set_repository.dart';
import 'package:dayseven/features/differences/domain/change_set.dart';
import 'package:dayseven/features/differences/ui/differences_workspace.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

ChangeSet proposal(String id, String username, String words) => ChangeSet(
  id: id,
  kbId: 'kb-1',
  documentId: null,
  targetDocumentId: 'doc-1',
  baseRevisionId: null,
  content: BlockDocument(
    id: 'doc-1',
    title: 'Shared Chronicle',
    blocks: [
      ParagraphBlock(
        id: 'paragraph-$id',
        spans: [TextSpanNode(text: words)],
      ),
    ],
  ),
  authorId: 'author-$username',
  authorUsername: username,
  authorDisplayName: username,
  status: ChangeSetStatus.pending,
  createdAt: DateTime.utc(2026, 8, 22),
  updatedAt: DateTime.utc(2026, 8, 22),
  operation: ChangeSetOperation.create,
  proposedPath: 'Shared Chronicle.md',
);

class Decisions implements ChangeSetDataSource {
  final approved = <String>[];
  final rejected = <String>[];

  @override
  Future<String?> approve({
    required String changeSetId,
    required BlockDocument merged,
    required String? expectedCurrentRevisionId,
    String? reviewNote,
  }) async {
    approved.add(changeSetId);
    return 'revision-$changeSetId';
  }

  @override
  Future<void> reject(String changeSetId, {String? reviewNote}) async {
    rejected.add(changeSetId);
  }

  @override
  Future<ChangeSet?> byId(String changeSetId) async => null;

  @override
  Future<List<ChangeSet>> pendingForKb(String kbId) async => const [];

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

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('owner reviews two collaborators on the same document', (
    tester,
  ) async {
    final alice = proposal(
      'alice-proposal',
      'alice',
      'Alice adds the eastern gate.',
    );
    final bob = proposal('bob-proposal', 'bob', 'Bob adds the western road.');
    final decisions = Decisions();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          differencesStateProvider.overrideWithValue(
            DifferencesState(
              proposals: [alice, bob],
              status: DifferencesLoadStatus.ready,
            ),
          ),
          changeSetRepositoryProvider.overrideWithValue(decisions),
        ],
        child: MaterialApp(
          theme: dsTheme(Brightness.dark),
          home: const Scaffold(body: DifferencesWorkspace()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('@alice'), findsOneWidget);
    expect(find.text('@bob'), findsOneWidget);

    await tester.tap(find.byKey(const Key('proposal-paper-alice-proposal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('proposal-paper-bob-proposal')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();

    expect(decisions.approved, ['alice-proposal']);
    expect(decisions.rejected, ['bob-proposal']);
  });
}
