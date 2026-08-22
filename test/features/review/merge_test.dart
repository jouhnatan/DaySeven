import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/features/review/domain/merge.dart';
import 'package:flutter_test/flutter_test.dart';

ParagraphBlock p(String id, String text, {bool bold = false, String? color}) =>
    ParagraphBlock(
      id: id,
      spans: [TextSpanNode(text: text, bold: bold, color: color)],
    );

ParagraphBlock spans(String id, List<TextSpanNode> s) =>
    ParagraphBlock(id: id, spans: s);

BlockDocument doc(List<Block> blocks, {String title = 'Aldenmoor'}) =>
    BlockDocument(id: 'doc-1', title: title, blocks: blocks);

String textOf(BlockDocument d, String blockId) =>
    d.blocks.firstWhere((b) => b.id == blockId).plainText;

ParagraphBlock paraOf(BlockDocument d, String blockId) =>
    d.blocks.firstWhere((b) => b.id == blockId) as ParagraphBlock;

void main() {
  group('three-way merge — title', () {
    test('different title edits are surfaced as a conflict', () {
      final base = doc(const [], title: 'Original');
      final result = threeWayMerge(
        base: base,
        local: doc(const [], title: 'Current title'),
        proposed: doc(const [], title: 'Proposed title'),
      );

      expect(result.titleConflict, isTrue);
      expect(result.hasConflicts, isTrue);
    });

    test('a proposal-only title edit merges without conflict', () {
      final base = doc(const [], title: 'Original');
      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc(const [], title: 'Proposed title'),
      );

      expect(result.document.title, 'Proposed title');
      expect(result.titleConflict, isFalse);
    });
  });

  group('three-way merge — block set', () {
    test('a paragraph added by only the proposal is kept', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc([p('a', 'The moor is wide.'), p('b', 'Fog sits low.')]),
      );
      expect(result.document.blocks.map((b) => b.id), ['a', 'b']);
      expect(result.hasConflicts, isFalse);
    });

    test('a paragraph added by only the local side is kept', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([p('a', 'The moor is wide.'), p('z', 'Local note.')]),
        proposed: base,
      );
      expect(result.document.blocks.map((b) => b.id), ['a', 'z']);
      expect(result.hasConflicts, isFalse);
    });

    test('additions from both sides are both kept', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([p('a', 'The moor is wide.'), p('z', 'Local note.')]),
        proposed: doc([p('a', 'The moor is wide.'), p('b', 'Fog sits low.')]),
      );
      expect(result.document.blocks.map((b) => b.id).toSet(), {'a', 'b', 'z'});
      expect(result.hasConflicts, isFalse);
    });

    test('a deletion on one side is honoured', () {
      final base = doc([p('a', 'First.'), p('b', 'Second.')]);
      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc([p('a', 'First.')]),
      );
      expect(result.document.blocks.map((b) => b.id), ['a']);
    });

    test('deletion on one side, edit on the other keeps the deletion', () {
      final base = doc([p('a', 'First.'), p('b', 'Second.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([p('a', 'First.'), p('b', 'Second, revised.')]),
        proposed: doc([p('a', 'First.')]),
      );
      expect(result.document.blocks.map((b) => b.id), ['a']);
    });
  });

  group('three-way merge — paragraph content', () {
    test('only the proposal edited: proposal wins, no conflict', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc([p('a', 'The moor is vast.')]),
      );
      expect(textOf(result.document, 'a'), 'The moor is vast.');
      expect(result.hasConflicts, isFalse);
    });

    test('only the local side edited: local survives', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([p('a', 'The moor is windy.')]),
        proposed: base,
      );
      expect(textOf(result.document, 'a'), 'The moor is windy.');
      expect(result.hasConflicts, isFalse);
    });

    test('both sides made the same edit: converges without conflict', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final edited = doc([p('a', 'The moor is vast.')]);
      final result = threeWayMerge(base: base, local: edited, proposed: edited);
      expect(textOf(result.document, 'a'), 'The moor is vast.');
      expect(result.hasConflicts, isFalse);
    });

    test('non-overlapping edits in one paragraph both survive', () {
      final base = doc([p('a', 'The moor is wide and the sky is grey.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([p('a', 'The fen is wide and the sky is grey.')]),
        proposed: doc([p('a', 'The moor is wide and the sky is black.')]),
      );
      expect(
        textOf(result.document, 'a'),
        'The fen is wide and the sky is black.',
      );
      expect(result.hasConflicts, isFalse);
    });

    test('overlapping edits conflict, and the proposal wins', () {
      final base = doc([p('a', 'The moor is wide.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([p('a', 'The moor is narrow.')]),
        proposed: doc([p('a', 'The moor is vast.')]),
      );
      expect(textOf(result.document, 'a'), 'The moor is vast.');
      expect(result.conflictedBlockIds, ['a']);
    });
  });

  group('three-way merge — formatting travels with characters', () {
    test('one side bolds a phrase while the other rewords elsewhere', () {
      final base = doc([
        spans('a', [const TextSpanNode(text: 'The moor is wide and cold.')]),
      ]);
      // Local bolds "moor".
      final local = doc([
        spans('a', const [
          TextSpanNode(text: 'The '),
          TextSpanNode(text: 'moor', bold: true),
          TextSpanNode(text: ' is wide and cold.'),
        ]),
      ]);
      // The proposal rewords the tail, touching no part of "moor".
      final proposed = doc([
        spans('a', const [TextSpanNode(text: 'The moor is wide and bitter.')]),
      ]);

      final result = threeWayMerge(
        base: base,
        local: local,
        proposed: proposed,
      );
      final merged = paraOf(result.document, 'a');

      expect(merged.plainText, 'The moor is wide and bitter.');
      expect(
        result.hasConflicts,
        isFalse,
        reason: 'the two sides touched different characters',
      );
      final boldRun = merged.spans
          .where((s) => s.bold)
          .map((s) => s.text)
          .join();
      expect(boldRun, 'moor', reason: 'the local bold must survive rewording');
    });

    test('a colour applied by one side survives an untouched merge', () {
      final base = doc([p('a', 'Aldenmoor')]);
      final local = doc([p('a', 'Aldenmoor', color: '#8A3B12')]);
      final result = threeWayMerge(base: base, local: local, proposed: base);
      expect(paraOf(result.document, 'a').spans.first.color, '#8A3B12');
      expect(result.hasConflicts, isFalse);
    });

    test(
      'both sides colour the same run differently: conflict, proposal wins',
      () {
        final base = doc([p('a', 'Aldenmoor')]);
        final result = threeWayMerge(
          base: base,
          local: doc([p('a', 'Aldenmoor', color: '#8A3B12')]),
          proposed: doc([p('a', 'Aldenmoor', color: '#123B8A')]),
        );
        expect(paraOf(result.document, 'a').spans.first.color, '#123B8A');
        expect(result.conflictedBlockIds, ['a']);
      },
    );
  });

  group('three-way merge — paragraph attributes and images', () {
    test('alignment changed by one side is taken', () {
      final base = doc([p('a', 'Centred later.')]);
      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc([
          ParagraphBlock(
            id: 'a',
            spans: const [TextSpanNode(text: 'Centred later.')],
            align: BlockAlign.center,
          ),
        ]),
      );
      expect(result.document.blocks.single.align, BlockAlign.center);
    });

    test('space before changed by the local side is preserved', () {
      final base = doc([p('a', 'Spaced.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([
          ParagraphBlock(
            id: 'a',
            spans: const [TextSpanNode(text: 'Spaced.')],
            spaceBefore: 18,
          ),
        ]),
        proposed: base,
      );
      expect(result.document.blocks.single.spaceBefore, 18);
    });

    test('an image caption edited by one side is taken', () {
      final base = doc([const ImageBlock(id: 'i', assetId: 'img_1')]);
      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc([
          const ImageBlock(id: 'i', assetId: 'img_1', caption: 'The east gate'),
        ]),
      );
      expect(
        (result.document.blocks.single as ImageBlock).caption,
        'The east gate',
      );
      expect(result.hasConflicts, isFalse);
    });
  });

  group('three-way merge — headings', () {
    HeadingBlock h(String id, int level, String text) => HeadingBlock(
      id: id,
      level: level,
      spans: [TextSpanNode(text: text)],
    );

    test('text merges the same way it does in a paragraph', () {
      final base = doc([h('a', 2, 'The Fen')]);
      final result = threeWayMerge(
        base: base,
        local: doc([h('a', 2, 'The Great Fen')]),
        proposed: base,
      );

      expect(textOf(result.document, 'a'), 'The Great Fen');
      expect(result.document.blocks.single, isA<HeadingBlock>());
      expect(result.hasConflicts, isFalse);
    });

    test('a level changed on one side is taken', () {
      final base = doc([h('a', 2, 'The Fen')]);
      final result = threeWayMerge(
        base: base,
        local: doc([h('a', 4, 'The Fen')]),
        proposed: base,
      );

      expect((result.document.blocks.single as HeadingBlock).level, 4);
      expect(result.hasConflicts, isFalse);
    });

    test('one side rewording while the other restyles keeps both', () {
      final base = doc([h('a', 1, 'The Fen')]);
      final result = threeWayMerge(
        base: base,
        local: doc([h('a', 1, 'The Great Fen')]),
        proposed: doc([
          HeadingBlock(
            id: 'a',
            level: 3,
            spans: const [TextSpanNode(text: 'The Fen')],
          ),
        ]),
      );

      expect(textOf(result.document, 'a'), 'The Great Fen');
      expect((result.document.blocks.single as HeadingBlock).level, 3);
    });

    test('alignment merges as it does for any block', () {
      final base = doc([h('a', 2, 'The Fen')]);
      final result = threeWayMerge(
        base: base,
        local: doc([
          HeadingBlock(
            id: 'a',
            level: 2,
            spans: const [TextSpanNode(text: 'The Fen')],
            align: BlockAlign.center,
          ),
        ]),
        proposed: base,
      );

      expect(result.document.blocks.single.align, BlockAlign.center);
    });

    /// The branch that catches this is `is TextBlock`, not a switch, so nothing
    /// would fail to compile if it were missing — the local side would just
    /// quietly disappear. This is the test that would notice.
    test('a heading is not silently replaced by the proposal', () {
      final base = doc([h('a', 2, 'The Fen')]);
      final result = threeWayMerge(
        base: base,
        local: doc([h('a', 2, 'The Fen, at dusk')]),
        proposed: doc([h('a', 2, 'The Fen')]),
      );

      expect(
        textOf(result.document, 'a'),
        'The Fen, at dusk',
        reason: 'the local edit survives an untouched proposal',
      );
    });

    test(
      'a paragraph turned into a heading on one side is a change of kind',
      () {
        final base = doc([p('a', 'The Fen')]);
        final result = threeWayMerge(
          base: base,
          local: doc([p('a', 'The Fen')]),
          proposed: doc([h('a', 2, 'The Fen')]),
        );

        expect(result.document.blocks.single, isA<HeadingBlock>());
      },
    );
  });

  group('document round-trip', () {
    test('encode then decode reproduces the document exactly', () {
      final original = doc([
        spans('a', const [
          TextSpanNode(text: 'Plain '),
          TextSpanNode(
            text: 'loud',
            bold: true,
            italic: true,
            strikethrough: true,
            underline: true,
            color: '#8A3B12',
            highlight: '#F2E7C9',
            font: 'Aleo',
          ),
        ]),
        const ImageBlock(
          id: 'i',
          assetId: 'img_1',
          caption: 'The east gate',
          align: BlockAlign.center,
          spaceBefore: 12,
        ),
      ]);
      final restored = BlockDocument.decode(original.encode());
      expect(restored.sameContentAs(original), isTrue);
      expect(restored.contentHash, original.contentHash);
    });
  });

  group('three-way merge — tables', () {
    TableBlock table(String a, String b, String c, String d) => TableBlock(
      id: 't',
      rows: [
        [
          [TextSpanNode(text: a)],
          [TextSpanNode(text: b)],
        ],
        [
          [TextSpanNode(text: c)],
          [TextSpanNode(text: d)],
        ],
      ],
    );

    String cell(BlockDocument document, int r, int c) =>
        (document.blocks.single as TableBlock).rows[r][c]
            .map((s) => s.text)
            .join();

    test('two people editing different cells both get their edit', () {
      final base = doc([table('a', 'b', 'c', 'd')]);
      final result = threeWayMerge(
        base: base,
        local: doc([table('a', 'LOCAL', 'c', 'd')]),
        proposed: doc([table('a', 'b', 'c', 'PROPOSED')]),
      );

      expect(cell(result.document, 0, 1), 'LOCAL');
      expect(cell(result.document, 1, 1), 'PROPOSED');
      expect(result.hasConflicts, isFalse);
    });

    test('the same cell edited differently conflicts', () {
      final base = doc([table('a', 'b', 'c', 'd')]);
      final result = threeWayMerge(
        base: base,
        local: doc([table('a', 'LOCAL', 'c', 'd')]),
        proposed: doc([table('a', 'PROPOSED', 'c', 'd')]),
      );

      expect(result.hasConflicts, isTrue);
    });

    test('a row added on one side is taken whole', () {
      final base = doc([table('a', 'b', 'c', 'd')]);
      final grown = TableBlock(
        id: 't',
        rows: [
          ...table('a', 'b', 'c', 'd').rows,
          [
            [const TextSpanNode(text: 'e')],
            [const TextSpanNode(text: 'f')],
          ],
        ],
      );

      final result = threeWayMerge(
        base: base,
        local: base,
        proposed: doc([grown]),
      );

      expect((result.document.blocks.single as TableBlock).rows, hasLength(3));
    });
  });

  group('three-way merge — footnotes', () {
    test('a note merges like any other text block', () {
      FootnoteBlock note(String text) => FootnoteBlock(
        id: 'f',
        label: '1',
        spans: [TextSpanNode(text: text)],
      );

      final base = doc([note('As recorded.')]);
      final result = threeWayMerge(
        base: base,
        local: doc([note('As recorded in the ledger.')]),
        proposed: base,
      );

      expect(textOf(result.document, 'f'), 'As recorded in the ledger.');
      expect(result.document.blocks.single, isA<FootnoteBlock>());
    });
  });
}
