/// Mapping a caret inside one block onto an offset in the whole file.
///
/// The CRDT holds each file as a single Y.Text of its Markdown, so a caret
/// that lives at offset 3 of a paragraph has to become an offset in the file
/// before it can be anchored and sent to a collaborator.
library;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

BlockDocument documentWith(List<Block> blocks) =>
    BlockDocument(id: 'doc-1', title: 'Aldric', blocks: blocks);

ParagraphBlock para(String id, String text) =>
    ParagraphBlock(id: id, spans: [TextSpanNode(text: text)]);

void main() {
  test('points at the first character of the block body', () {
    final document = documentWith([
      para('p-1', 'The moor is wide.'),
      para('p-2', 'Beyond it, the sea.'),
    ]);
    final markdown = encodeMarkdown(document);

    final first = markdownBodyOffsetOfBlock(markdown, 'p-1')!;
    expect(markdown.substring(first, first + 17), 'The moor is wide.');

    final second = markdownBodyOffsetOfBlock(markdown, 'p-2')!;
    expect(markdown.substring(second, second + 19), 'Beyond it, the sea.');
  });

  test('a caret offset within a block lands on the right character', () {
    final document = documentWith([
      para('p-1', 'The moor is wide.'),
      para('p-2', 'Beyond it, the sea.'),
    ]);
    final markdown = encodeMarkdown(document);
    // "Beyond it, the sea." — "the" begins at block offset 11.
    final start = markdownBodyOffsetOfBlock(markdown, 'p-2')!;
    expect(markdown.substring(start + 11, start + 14), 'the');
  });

  test('offsets are UTF-16, matching every other offset in the system', () {
    final document = documentWith([para('p-1', 'Ωετες lies east')]);
    final markdown = encodeMarkdown(document);
    final start = markdownBodyOffsetOfBlock(markdown, 'p-1')!;
    expect(markdown.substring(start, start + 5), 'Ωετες');
  });

  test('a heading is located the same way as a paragraph', () {
    final document = documentWith([
      const HeadingBlock(
        id: 'h-1',
        level: 2,
        spans: [TextSpanNode(text: 'Aldenmoor')],
      ),
      para('p-1', 'The moor is wide.'),
    ]);
    final markdown = encodeMarkdown(document);
    final start = markdownBodyOffsetOfBlock(markdown, 'h-1')!;
    expect(markdown.substring(start).startsWith('## Aldenmoor'), isTrue);
  });

  test('a block that is not there returns null rather than guessing', () {
    final markdown = encodeMarkdown(documentWith([para('p-1', 'Only one.')]));
    expect(markdownBodyOffsetOfBlock(markdown, 'p-missing'), isNull);
  });

  test('an empty document has no block offsets', () {
    final markdown = encodeMarkdown(documentWith([]));
    expect(markdownBodyOffsetOfBlock(markdown, 'p-1'), isNull);
  });

  test('a block id that prefixes another is not confused for it', () {
    // 'p-1' is a prefix of 'p-10'. Matching on the marker text alone would
    // find the wrong block.
    final document = documentWith([
      para('p-10', 'Tenth.'),
      para('p-1', 'First.'),
    ]);
    final markdown = encodeMarkdown(document);
    final tenth = markdownBodyOffsetOfBlock(markdown, 'p-10')!;
    final first = markdownBodyOffsetOfBlock(markdown, 'p-1')!;
    expect(markdown.substring(tenth, tenth + 6), 'Tenth.');
    expect(markdown.substring(first, first + 6), 'First.');
  });
}
