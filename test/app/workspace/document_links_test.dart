import 'dart:io';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/kb_harness.dart';

void main() {
  late Directory temp;

  setUp(() async {
    final dirs = await createTempDirs('dayseven_document_links');
    temp = dirs.temp;
  });

  testWidgets('rename rewrites persisted backlinks and their search rows', (
    tester,
  ) async {
    final (container, kb) = await openTestKb(tester, temp);

    await tester.runAsync(() async {
      await kb.createFolder('People');
      await kb.createFolder('Places');
      final person = await kb.createDocument(
        title: 'Aldric',
        folderRelativePath: 'People',
      );
      final place = await kb.createDocument(
        title: 'Old Fen',
        folderRelativePath: 'Places',
      );
      await kb.writeDocument(
        person,
        BlockDocument(
          id: 'person',
          title: 'Aldric',
          blocks: [
            ParagraphBlock(
              id: 'p1',
              spans: const [
                TextSpanNode(text: 'Old Fen', href: '../Places/Old Fen.md'),
              ],
            ),
          ],
        ),
      );
      await container.read(kbControllerProvider.notifier).refreshTree();
      await container.read(documentControllerProvider.notifier).open(person);
      final open = container.read(documentControllerProvider)!;
      container
          .read(documentControllerProvider.notifier)
          .edit(
            open.document.copyWith(
              blocks: [
                ParagraphBlock(
                  id: 'p1',
                  spans: const [
                    TextSpanNode(text: 'Unsaved note about '),
                    TextSpanNode(text: 'Old Fen', href: '../Places/Old Fen.md'),
                  ],
                ),
              ],
            ),
          );
      await container
          .read(kbControllerProvider.notifier)
          .renameDocument(place, 'Aldenmoor');
    });

    final document = await tester.runAsync(
      () => kb.readDocument('People/Aldric.md'),
    );
    final spans = (document!.blocks.single as ParagraphBlock).spans;
    expect(spans.first.text, 'Unsaved note about ');
    expect(spans.last.text, 'Aldenmoor');
    expect(spans.last.href, '../Places/Aldenmoor.md');
    expect(
      container
          .read(kbSessionProvider)!
          .index
          .search('Aldenmoor')
          .map((result) => result.relativePath),
      contains('People/Aldric.md'),
    );
  });
}
