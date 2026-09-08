import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/document_links.dart';
import 'package:flutter_test/flutter_test.dart';

BlockDocument _document(String id, String title, List<TextSpanNode> spans) =>
    BlockDocument(
      id: id,
      title: title,
      blocks: [ParagraphBlock(id: 'p-$id', spans: spans)],
    );

List<TextSpanNode> _spans(BlockDocument document) =>
    (document.blocks.single as ParagraphBlock).spans;

void main() {
  test('resolves a portable Markdown path relative to its source', () {
    final target = resolveDocumentLink(
      'People/Keepers/Aldric.md',
      '../../Places/The Fen.md#north',
    );

    expect(target?.path, 'Places/The Fen.md');
    expect(target?.fragment, '#north');
    expect(
      documentLinkHref('People/Keepers/Aldric.md', 'Places/The Fen.md'),
      '../../Places/The Fen.md',
    );
  });

  test('renaming a target rewrites its label and every relative href', () {
    final rewritten = rewriteDocumentLinksForMove(
      documents: {
        'People/Aldric.md': _document('a', 'Aldric', const [
          TextSpanNode(text: 'Visit '),
          TextSpanNode(text: 'Old Fen', href: '../Places/Old Fen.md#gate'),
          TextSpanNode(text: ' online', href: 'https://example.com'),
        ]),
        'Places/Old Fen.md': _document('f', 'Old Fen', const []),
      },
      fromPath: 'Places/Old Fen.md',
      toPath: 'Places/Aldenmoor.md',
      renameMovedDocumentTitle: true,
    );

    final link = _spans(rewritten['People/Aldric.md']!)[1];
    expect(link.text, 'Aldenmoor');
    expect(link.href, '../Places/Aldenmoor.md#gate');
    expect(
      _spans(rewritten['People/Aldric.md']!)[2].href,
      'https://example.com',
    );
    expect(rewritten['Places/Aldenmoor.md']!.title, 'Aldenmoor');
  });

  test('moving a referring folder recalculates links from the new source', () {
    final rewritten = rewriteDocumentLinksForMove(
      documents: {
        'Drafts/Notes.md': _document('n', 'Notes', const [
          TextSpanNode(text: 'Aldenmoor', href: '../Places/Aldenmoor.md'),
        ]),
        'Places/Aldenmoor.md': _document('a', 'Aldenmoor', const []),
      },
      fromPath: 'Drafts',
      toPath: 'Archive/Drafts',
    );

    expect(
      _spans(rewritten['Archive/Drafts/Notes.md']!).single.href,
      '../../Places/Aldenmoor.md',
    );
  });
}
