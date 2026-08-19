/// The Markdown codec is where a bug would silently corrupt a user's writing,
/// so the round trip is tested attribute by attribute rather than by sampling.
library;

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/markdown.dart';
import 'package:flutter_test/flutter_test.dart';

BlockDocument docOf(List<Block> blocks, {String title = 'Aldenmoor'}) =>
    BlockDocument(id: 'doc-1', title: title, blocks: blocks);

ParagraphBlock para(List<TextSpanNode> spans, {String id = 'b1'}) =>
    ParagraphBlock(id: id, spans: spans);

/// Round trips [document] and returns what came back.
BlockDocument cycle(BlockDocument document) =>
    decodeMarkdown(encodeMarkdown(document));

void expectSurvives(BlockDocument document, {String? reason}) {
  final back = cycle(document);
  expect(back.sameContentAs(document), isTrue, reason: reason);
  expect(back.contentHash, document.contentHash, reason: reason);
}

void main() {
  group('every span attribute survives', () {
    final cases = <String, TextSpanNode>{
      'plain': TextSpanNode(text: 'plain'),
      'bold': TextSpanNode(text: 'bold', bold: true),
      'italic': TextSpanNode(text: 'italic', italic: true),
      'strikethrough': TextSpanNode(text: 'struck', strikethrough: true),
      'underline': TextSpanNode(text: 'under', underline: true),
      'color': TextSpanNode(text: 'red', color: '#8A3B12'),
      'highlight': TextSpanNode(text: 'lit', highlight: '#F2E7C9'),
      'font': TextSpanNode(text: 'serif', font: 'Times New Roman'),
      'everything at once': TextSpanNode(
        text: 'all',
        bold: true,
        italic: true,
        strikethrough: true,
        underline: true,
        color: '#123456',
        highlight: '#ABCDEF',
        font: 'Georgia',
      ),
    };

    cases.forEach((name, span) {
      test(
        name,
        () => expectSurvives(
          docOf([
            para([span]),
          ]),
        ),
      );
    });
  });

  group('block attributes survive', () {
    for (final align in BlockAlign.values) {
      test('align ${align.name}', () {
        expectSurvives(
          docOf([
            ParagraphBlock(
              id: 'b1',
              spans: const [TextSpanNode(text: 'aligned')],
              align: align,
            ),
          ]),
        );
      });
    }

    test('spaceBefore, whole and fractional', () {
      for (final space in [16.0, 0.5, 12.25]) {
        expectSurvives(
          docOf([
            ParagraphBlock(
              id: 'b1',
              spans: const [TextSpanNode(text: 'spaced')],
              spaceBefore: space,
            ),
          ]),
          reason: 'spaceBefore $space',
        );
      }
    });

    test('block ids are preserved, which the merge aligns by', () {
      final document = docOf([
        para(const [TextSpanNode(text: 'one')], id: 'first'),
        para(const [TextSpanNode(text: 'two')], id: 'second'),
      ]);
      expect(cycle(document).blocks.map((b) => b.id), ['first', 'second']);
    });
  });

  group('headings', () {
    for (var level = 1; level <= 6; level++) {
      test('level $level', () {
        expectSurvives(
          docOf([
            HeadingBlock(
              id: 'h',
              level: level,
              spans: const [TextSpanNode(text: 'The Fen')],
            ),
          ]),
        );
      });
    }

    test('inline formatting works inside a heading', () {
      expectSurvives(
        docOf([
          HeadingBlock(
            id: 'h',
            level: 2,
            spans: const [
              TextSpanNode(text: 'The '),
              TextSpanNode(text: 'Fen', bold: true),
            ],
          ),
        ]),
      );
    });

    test('a heading with alignment keeps both', () {
      expectSurvives(
        docOf([
          HeadingBlock(
            id: 'h',
            level: 3,
            spans: const [TextSpanNode(text: 'Centred')],
            align: BlockAlign.center,
          ),
        ]),
      );
    });
  });

  group('images', () {
    test('with and without a caption', () {
      expectSurvives(
        docOf([
          ImageBlock(id: 'i1', assetId: 'a.png', caption: 'The fen at dusk'),
          ImageBlock(id: 'i2', assetId: 'b.png'),
        ]),
      );
    });

    test('a caption containing brackets and parentheses', () {
      expectSurvives(
        docOf([
          ImageBlock(id: 'i', assetId: 'a.png', caption: 'a [b] (c) \\ d'),
        ]),
      );
    });

    test('only the file name is kept, so a move need not rewrite the file', () {
      final decoded = decodeMarkdown('''
---
d7: 1
id: "doc-1"
title: "T"
---

<!-- d7 i -->
![cap](../../elsewhere/.settings/assets/a.png)
''');
      expect((decoded.blocks.single as ImageBlock).assetId, 'a.png');
    });
  });

  group('escaping', () {
    final texts = <String, String>{
      'asterisks': 'a * b ** c',
      'underscores': 'snake_case and _more_',
      'tildes': 'a ~ b ~~ c',
      'backticks': 'a `code` b',
      'brackets': 'a [link] b',
      'angle brackets': 'a < b > c',
      'ampersand': 'Tom & Jerry &amp; friends',
      'backslash': r'a \ b \\ c',
      'a leading hash': '# not a heading',
      'a leading dash': '- not a list',
      'a leading quote': '> not a quote',
      'a leading number': '1. not ordered',
      'a leading pipe': '| not a table',
      'exactly three dashes': '---',
      'an image that is not one': '![not](an-image.png)',
      'an html comment': '<!-- d7 not-an-id -->',
      'interior newline': 'first line\nsecond line',
      'quotes': 'she said "hello" and \'bye\'',
    };

    texts.forEach((name, text) {
      test(name, () {
        expectSurvives(
          docOf([
            para([TextSpanNode(text: text)]),
          ]),
          reason: text,
        );
      });
    });

    test('escapable text keeps its formatting too', () {
      expectSurvives(
        docOf([
          para(const [
            TextSpanNode(
              text: '# starts with a hash',
              bold: true,
              italic: true,
            ),
          ]),
        ]),
      );
    });
  });

  group('whitespace-only and empty spans', () {
    test('a formatted span that is only whitespace', () {
      expectSurvives(
        docOf([
          para(const [
            TextSpanNode(text: 'a'),
            TextSpanNode(text: ' ', italic: true),
            TextSpanNode(text: 'b'),
          ]),
        ]),
      );
    });

    test('a formatted span with leading and trailing spaces', () {
      expectSurvives(
        docOf([
          para(const [TextSpanNode(text: ' padded ', bold: true)]),
        ]),
      );
    });

    test('an empty paragraph — the shape of every new document', () {
      expectSurvives(docOf([para(const [])]));
    });

    test('an empty paragraph between two full ones', () {
      expectSurvives(
        docOf([
          para(const [TextSpanNode(text: 'one')], id: 'a'),
          para(const [], id: 'b'),
          para(const [TextSpanNode(text: 'two')], id: 'c'),
        ]),
      );
    });

    test('a document with no blocks at all', () {
      expectSurvives(docOf(const []));
    });

    test('an empty title', () {
      expectSurvives(docOf([para(const [])], title: ''));
    });

    test('a title needing quoting', () {
      expectSurvives(
        docOf([para(const [])], title: 'A: "quoted", with \\ and é'),
      );
    });
  });

  group('canonical form', () {
    test('encoding is idempotent', () {
      final document = docOf([
        HeadingBlock(
          id: 'h',
          level: 2,
          spans: const [TextSpanNode(text: 'The Fen')],
        ),
        ParagraphBlock(
          id: 'p',
          spans: const [
            TextSpanNode(text: 'wide ', bold: true),
            TextSpanNode(text: 'and cold', color: '#8A3B12'),
          ],
          align: BlockAlign.center,
          spaceBefore: 16,
        ),
        ImageBlock(id: 'i', assetId: 'a.png', caption: 'dusk'),
      ]);

      final once = encodeMarkdown(document);
      expect(encodeMarkdown(decodeMarkdown(once)), once);
    });

    test('adjacent same-format spans collapse to the canonical form', () {
      final document = docOf([
        para(const [
          TextSpanNode(text: 'one', bold: true),
          TextSpanNode(text: ' two', bold: true),
        ]),
      ]);

      expect(
        cycle(document).sameContentAs(
          docOf([
            para(const [TextSpanNode(text: 'one two', bold: true)]),
          ]),
        ),
        isTrue,
      );
    });

    /// Pins the bytes, so a change to the format shows up in review rather than
    /// silently rewriting every document in the user's library.
    test('golden', () {
      final document = BlockDocument(
        id: 'doc-1',
        title: 'Aldenmoor',
        blocks: [
          HeadingBlock(
            id: 'h1',
            level: 2,
            spans: const [TextSpanNode(text: 'The Fen')],
          ),
          ParagraphBlock(
            id: 'p1',
            spans: const [
              TextSpanNode(text: 'The moor is '),
              TextSpanNode(text: 'wide', bold: true),
              TextSpanNode(text: ' and '),
              TextSpanNode(text: 'cold', underline: true),
              TextSpanNode(text: '.'),
            ],
          ),
          ParagraphBlock(
            id: 'p2',
            spans: const [
              TextSpanNode(text: 'Aldenmoor', color: '#8A3B12'),
              TextSpanNode(text: ', the last free hold.'),
            ],
            align: BlockAlign.center,
            spaceBefore: 16,
          ),
          ImageBlock(id: 'i1', assetId: 'fen.png', caption: 'At dusk'),
        ],
      );

      expect(encodeMarkdown(document), '''
---
d7: 1
schema: 1
id: "doc-1"
title: "Aldenmoor"
---

<!-- d7 h1 -->
## The Fen

<!-- d7 p1 -->
The moor is **wide** and <u>cold</u>.

<!-- d7 p2 align=center space=16 -->
<span style="color:#8A3B12">Aldenmoor</span>, the last free hold.

<!-- d7 i1 -->
![At dusk](.settings/assets/fen.png)
''');
    });
  });

  group('tolerating hand-edited files', () {
    test('a plain Markdown file with no d7 comments still opens', () {
      final decoded = decodeMarkdown('''
# A Title

Some **bold** text.

Another paragraph.
''');

      expect(decoded.blocks, hasLength(3));
      expect(decoded.blocks.first, isA<HeadingBlock>());
      expect(
        (decoded.blocks[1] as ParagraphBlock).plainText,
        'Some bold text.',
      );
      // Ids are minted so the merge still has something to align by.
      expect(decoded.blocks.map((b) => b.id).toSet(), hasLength(3));
    });

    test(
      'an unrecognised construct becomes a paragraph rather than vanishing',
      () {
        final decoded = decodeMarkdown('''
---
d7: 1
id: "d"
title: "T"
---

| a | table |
''');
        expect(decoded.blocks.single, isA<ParagraphBlock>());
        expect(decoded.blocks.single.plainText, '| a | table |');
      },
    );

    test('malformed attributes fall back to defaults', () {
      final decoded = decodeMarkdown('''
<!-- d7 b1 align=sideways space=banana -->
Text.
''');
      expect(decoded.blocks.single.align, BlockAlign.left);
      expect(decoded.blocks.single.spaceBefore, 0);
      expect(decoded.blocks.single.id, 'b1');
    });

    test('a missing frontmatter block still yields a document', () {
      final decoded = decodeMarkdown('Just text.\n');
      expect(decoded.blocks.single.plainText, 'Just text.');
      expect(decoded.id, isNotEmpty);
    });
  });

  group('the hash a save produces', () {
    /// The quiet one. `contentHash` decides whether a local file still matches
    /// the revision it came from, and Markdown cannot represent two adjacent
    /// spans that share formatting. If a document reaches the app in that
    /// shape, saving it would change its hash and it would look diverged from
    /// the server days later, with nothing obviously wrong.
    test('does not change for a document the app actually holds', () {
      final canonical = docOf([
        para(const [
          TextSpanNode(text: 'one two', bold: true),
          TextSpanNode(text: ' three'),
        ]),
      ]);

      expect(cycle(canonical).contentHash, canonical.contentHash);
    });

    test('normalized() is what makes any document safe to save', () {
      final loose = docOf([
        para(const [
          TextSpanNode(text: 'one', bold: true),
          TextSpanNode(text: ' two', bold: true),
          TextSpanNode(text: ' three'),
        ]),
      ]);

      // As-is the hash moves, which is the trap.
      expect(cycle(loose).contentHash, isNot(loose.contentHash));

      // Canonicalised first, it holds — and that is what the import path does.
      final safe = loose.normalized();
      expect(cycle(safe).contentHash, safe.contentHash);
    });
  });
  group('links', () {
    test('a link survives, with and without other formatting', () {
      expectSurvives(
        docOf([
          para(const [
            TextSpanNode(text: 'see '),
            TextSpanNode(text: 'the fen', href: 'https://example.com/fen'),
            TextSpanNode(text: ' and '),
            TextSpanNode(
              text: 'this',
              href: 'a/b.md',
              bold: true,
              italic: true,
            ),
          ]),
        ]),
      );
    });

    test('a url containing brackets and spaces survives', () {
      expectSurvives(
        docOf([
          para(const [TextSpanNode(text: 'x', href: 'https://e.com/a (b) c')]),
        ]),
      );
    });

    test('bracketed text that is not a link is not turned into one', () {
      expectSurvives(
        docOf([
          para(const [TextSpanNode(text: 'an [aside] here')]),
        ]),
      );
    });
  });

  group('lists', () {
    test('bullets, numbers, nesting and tasks all survive', () {
      expectSurvives(
        docOf([
          ListItemBlock(
            id: 'l1',
            spans: const [TextSpanNode(text: 'one')],
          ),
          ListItemBlock(
            id: 'l2',
            spans: const [TextSpanNode(text: 'nested')],
            depth: 1,
          ),
          ListItemBlock(
            id: 'l3',
            spans: const [TextSpanNode(text: 'numbered')],
            style: ListStyle.ordered,
          ),
          ListItemBlock(
            id: 'l4',
            spans: const [TextSpanNode(text: 'todo')],
            checked: false,
          ),
          ListItemBlock(
            id: 'l5',
            spans: const [TextSpanNode(text: 'done')],
            checked: true,
          ),
        ]),
      );
    });

    test('inline formatting works inside an item', () {
      expectSurvives(
        docOf([
          ListItemBlock(
            id: 'l1',
            spans: const [
              TextSpanNode(text: 'bold', bold: true),
              TextSpanNode(text: ' and plain'),
            ],
            depth: 2,
            style: ListStyle.ordered,
          ),
        ]),
      );
    });

    test('a hand-written list is read', () {
      final decoded = decodeMarkdown(
        '- one\n* two\n1. three\n2) four\n  - nested\n'
        '- [ ] todo\n- [x] done\n',
      );
      final items = decoded.blocks.cast<ListItemBlock>();
      expect(items, hasLength(7));
      expect(items[0].style, ListStyle.bullet);
      expect(items[2].style, ListStyle.ordered);
      expect(items[3].style, ListStyle.ordered);
      expect(items[4].depth, 1);
      expect(items[5].checked, isFalse);
      expect(items[6].checked, isTrue);
    });
  });

  group('quotes, code and rules', () {
    test('a quote survives, formatting included', () {
      expectSurvives(
        docOf([
          QuoteBlock(
            id: 'q',
            spans: const [
              TextSpanNode(text: 'The moor '),
              TextSpanNode(text: 'remembers', italic: true),
            ],
          ),
        ]),
      );
    });

    test('a divider survives', () {
      expectSurvives(
        docOf([
          para(const [TextSpanNode(text: 'above')], id: 'a'),
          DividerBlock(id: 'd'),
          para(const [TextSpanNode(text: 'below')], id: 'b'),
        ]),
      );
    });

    test('code survives, including blank lines and its language', () {
      expectSurvives(
        docOf([
          CodeBlock(
            id: 'c',
            language: 'dart',
            text: 'void main() {\n\n  print("hi");\n}',
          ),
        ]),
      );
    });

    test('code with no language survives', () {
      expectSurvives(docOf([CodeBlock(id: 'c', text: 'plain')]));
    });

    /// Code is verbatim, so none of the usual escaping applies inside it.
    test('code containing markup is left exactly as written', () {
      const source = '# not a heading\n- not a list\n**not bold** <u>x</u>';
      final back = cycle(docOf([CodeBlock(id: 'c', text: source)]));
      expect((back.blocks.single as CodeBlock).text, source);
      expectSurvives(docOf([CodeBlock(id: 'c', text: source)]));
    });

    test('code containing a fence gets a longer one', () {
      expectSurvives(docOf([CodeBlock(id: 'c', text: 'a\n```\nb')]));
    });
  });

  group('a document using everything at once', () {
    BlockDocument everything() => docOf([
      HeadingBlock(
        id: 'h',
        level: 1,
        spans: const [TextSpanNode(text: 'Aldenmoor')],
      ),
      para(const [
        TextSpanNode(text: 'The '),
        TextSpanNode(text: 'fen', bold: true, href: 'https://e.com'),
      ], id: 'p'),
      QuoteBlock(
        id: 'q',
        spans: const [TextSpanNode(text: 'It waits.')],
      ),
      ListItemBlock(
        id: 'l',
        spans: const [TextSpanNode(text: 'reeds')],
      ),
      ListItemBlock(
        id: 'l2',
        spans: const [TextSpanNode(text: 'water')],
        depth: 1,
        checked: true,
      ),
      CodeBlock(id: 'c', language: 'sh', text: 'echo hi'),
      DividerBlock(id: 'd'),
      ImageBlock(id: 'i', assetId: 'fen.png', caption: 'dusk'),
    ]);

    test('survives', () => expectSurvives(everything()));

    test('is idempotent', () {
      final once = encodeMarkdown(everything());
      expect(encodeMarkdown(decodeMarkdown(once)), once);
    });
  });
}
