/// The DaySeven document model.
///
/// One paragraph is one block, Notion-style. Blocks carry stable ids so that a
/// three-way merge can align them by identity rather than by position: a
/// paragraph that moved is the same paragraph, not a delete plus an insert.
///
/// This JSON is what is stored in `revisions.content` and what the diff view
/// compares. On disk the same model is written as Markdown — see
/// `markdown.dart`; this stays the canonical in-memory and over-the-wire shape.
/// Pure Dart — nothing in this file may import Flutter or Supabase.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// Bumped when this JSON shape changes in a way that needs migration. It
/// travels into `revisions.content`, so it tracks the *model*, not the file
/// format — the Markdown encoding has its own [kMarkdownFormatVersion].
const int kDocumentSchemaVersion = 1;

enum BlockAlign { left, center, right }

BlockAlign _alignFrom(Object? v) => switch (v) {
  'center' => BlockAlign.center,
  'right' => BlockAlign.right,
  _ => BlockAlign.left,
};

/// A run of text sharing one set of inline formats.
class TextSpanNode {
  const TextSpanNode({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.underline = false,
    this.color,
    this.highlight,
    this.font,
    this.href,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool underline;

  /// `#RRGGBB`, or null to inherit the editor's default text colour.
  final String? color;

  /// `#RRGGBB`, or null for no highlight.
  final String? highlight;

  /// Font family name, or null for the document default (Aleo).
  final String? font;

  /// Link target, or null for ordinary text.
  final String? href;

  bool get isEmpty => text.isEmpty;

  /// True when two spans differ only in their text, and so can be concatenated.
  bool sameFormatting(TextSpanNode other) =>
      bold == other.bold &&
      italic == other.italic &&
      strikethrough == other.strikethrough &&
      underline == other.underline &&
      color == other.color &&
      highlight == other.highlight &&
      font == other.font &&
      href == other.href;

  TextSpanNode copyWith({String? text}) => TextSpanNode(
    text: text ?? this.text,
    bold: bold,
    italic: italic,
    strikethrough: strikethrough,
    underline: underline,
    color: color,
    highlight: highlight,
    font: font,
    href: href,
  );

  /// Omits every default so documents stay small and diffs stay readable.
  Map<String, Object?> toJson() => {
    'text': text,
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (strikethrough) 'strikethrough': true,
    if (underline) 'underline': true,
    if (color != null) 'color': color,
    if (highlight != null) 'highlight': highlight,
    if (font != null) 'font': font,
    if (href != null) 'href': href,
  };

  static TextSpanNode fromJson(Map<String, Object?> json) => TextSpanNode(
    text: json['text'] as String? ?? '',
    bold: json['bold'] == true,
    italic: json['italic'] == true,
    strikethrough: json['strikethrough'] == true,
    underline: json['underline'] == true,
    color: json['color'] as String?,
    highlight: json['highlight'] as String?,
    font: json['font'] as String?,
    href: json['href'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is TextSpanNode && other.text == text && sameFormatting(other);

  @override
  int get hashCode => Object.hash(
    text,
    bold,
    italic,
    strikethrough,
    underline,
    color,
    highlight,
    font,
    href,
  );
}

sealed class Block {
  const Block({
    required this.id,
    this.align = BlockAlign.left,
    this.spaceBefore = 0,
  });

  final String id;
  final BlockAlign align;

  /// Space before the paragraph, in logical pixels.
  final double spaceBefore;

  Map<String, Object?> toJson();

  /// The block's text, used for merge comparison and the search index.
  String get plainText;

  /// Copies the block, changing only what every block has. Lets callers that
  /// do not care what kind of block this is — alignment, spacing — avoid a
  /// switch that would need a new arm for every future block type.
  Block copyWithCommon({BlockAlign? align, double? spaceBefore});

  /// An unrecognised type decodes as a paragraph rather than failing, so a
  /// document written by a newer build still opens with its text intact.
  static Block fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'image' => ImageBlock.fromJson(json),
      'heading' => HeadingBlock.fromJson(json),
      'listItem' => ListItemBlock.fromJson(json),
      'quote' => QuoteBlock.fromJson(json),
      'code' => CodeBlock.fromJson(json),
      'divider' => DividerBlock.fromJson(json),
      _ => ParagraphBlock.fromJson(json),
    };
  }

  Map<String, Object?> _common() => {
    'id': id,
    if (align != BlockAlign.left) 'align': align.name,
    if (spaceBefore != 0) 'spaceBefore': spaceBefore,
  };
}

/// A block whose content is a run of formatted text.
///
/// Paragraphs and headings differ only in how they are drawn, so everything
/// that works on spans — the merge, the diff view, the editor's controllers —
/// takes one of these and does not care which it has.
sealed class TextBlock extends Block {
  const TextBlock({required super.id, super.align, super.spaceBefore});

  List<TextSpanNode> get spans;

  /// The same block with different text, keeping its id, kind and formatting.
  TextBlock withSpans(List<TextSpanNode> spans);

  /// Merges adjacent spans that share formatting and drops empty ones, so that
  /// two blocks with the same appearance also have the same JSON.
  TextBlock normalized() {
    final out = <TextSpanNode>[];
    for (final span in spans) {
      if (span.isEmpty) continue;
      if (out.isNotEmpty && out.last.sameFormatting(span)) {
        out[out.length - 1] = out.last.copyWith(
          text: out.last.text + span.text,
        );
      } else {
        out.add(span);
      }
    }
    return withSpans(out);
  }

  @override
  String get plainText => spans.map((s) => s.text).join();
}

class ParagraphBlock extends TextBlock {
  const ParagraphBlock({
    required super.id,
    required this.spans,
    super.align,
    super.spaceBefore,
  });

  @override
  final List<TextSpanNode> spans;

  @override
  ParagraphBlock withSpans(List<TextSpanNode> spans) => copyWith(spans: spans);

  @override
  ParagraphBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      copyWith(align: align, spaceBefore: spaceBefore);

  ParagraphBlock copyWith({
    List<TextSpanNode>? spans,
    BlockAlign? align,
    double? spaceBefore,
  }) => ParagraphBlock(
    id: id,
    spans: spans ?? this.spans,
    align: align ?? this.align,
    spaceBefore: spaceBefore ?? this.spaceBefore,
  );

  @override
  ParagraphBlock normalized() => super.normalized() as ParagraphBlock;

  @override
  Map<String, Object?> toJson() => {
    ..._common(),
    'type': 'paragraph',
    'spans': spans.map((s) => s.toJson()).toList(),
  };

  static ParagraphBlock fromJson(Map<String, Object?> json) => ParagraphBlock(
    id: json['id'] as String,
    spans: (json['spans'] as List<Object?>? ?? const [])
        .map((s) => TextSpanNode.fromJson(s as Map<String, Object?>))
        .toList(),
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

/// A heading. Carries spans like a paragraph, so inline formatting works
/// inside one and the editor reuses the same controller for both.
class HeadingBlock extends TextBlock {
  const HeadingBlock({
    required super.id,
    required this.level,
    required this.spans,
    super.align,
    super.spaceBefore,
  });

  /// 1 through 6, matching Markdown's `#` through `######`.
  final int level;

  @override
  final List<TextSpanNode> spans;

  @override
  HeadingBlock withSpans(List<TextSpanNode> spans) => copyWith(spans: spans);

  @override
  HeadingBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      copyWith(align: align, spaceBefore: spaceBefore);

  @override
  HeadingBlock normalized() => super.normalized() as HeadingBlock;

  HeadingBlock copyWith({
    int? level,
    List<TextSpanNode>? spans,
    BlockAlign? align,
    double? spaceBefore,
  }) => HeadingBlock(
    id: id,
    level: level ?? this.level,
    spans: spans ?? this.spans,
    align: align ?? this.align,
    spaceBefore: spaceBefore ?? this.spaceBefore,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._common(),
    'type': 'heading',
    'level': level,
    'spans': spans.map((s) => s.toJson()).toList(),
  };

  static HeadingBlock fromJson(Map<String, Object?> json) => HeadingBlock(
    id: json['id'] as String,
    level: ((json['level'] as num?)?.toInt() ?? 1).clamp(1, 6),
    spans: (json['spans'] as List<Object?>? ?? const [])
        .map((s) => TextSpanNode.fromJson(s as Map<String, Object?>))
        .toList(),
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

/// Whether a list item is bulleted or numbered.
enum ListStyle { bullet, ordered }

ListStyle _listStyleFrom(Object? v) =>
    v == 'ordered' ? ListStyle.ordered : ListStyle.bullet;

/// One line of a list. Items are separate blocks rather than children of a
/// list, so that the merge keeps aligning by id the way it does everywhere
/// else, and so that indenting a line is an attribute change rather than a
/// move between parents.
class ListItemBlock extends TextBlock {
  const ListItemBlock({
    required super.id,
    required this.spans,
    this.style = ListStyle.bullet,
    this.depth = 0,
    this.checked,
    super.align,
    super.spaceBefore,
  });

  final ListStyle style;

  /// Nesting level; 0 is the outermost.
  final int depth;

  /// null for an ordinary item, true or false for a task item.
  final bool? checked;

  @override
  final List<TextSpanNode> spans;

  @override
  ListItemBlock withSpans(List<TextSpanNode> spans) => copyWith(spans: spans);

  @override
  ListItemBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      copyWith(align: align, spaceBefore: spaceBefore);

  @override
  ListItemBlock normalized() => super.normalized() as ListItemBlock;

  ListItemBlock copyWith({
    List<TextSpanNode>? spans,
    ListStyle? style,
    int? depth,
    bool? checked,
    bool clearChecked = false,
    BlockAlign? align,
    double? spaceBefore,
  }) => ListItemBlock(
    id: id,
    spans: spans ?? this.spans,
    style: style ?? this.style,
    depth: depth ?? this.depth,
    checked: clearChecked ? null : (checked ?? this.checked),
    align: align ?? this.align,
    spaceBefore: spaceBefore ?? this.spaceBefore,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._common(),
    'type': 'listItem',
    if (style != ListStyle.bullet) 'style': style.name,
    if (depth != 0) 'depth': depth,
    if (checked != null) 'checked': checked,
    'spans': spans.map((s) => s.toJson()).toList(),
  };

  static ListItemBlock fromJson(Map<String, Object?> json) => ListItemBlock(
    id: json['id'] as String,
    style: _listStyleFrom(json['style']),
    depth: ((json['depth'] as num?)?.toInt() ?? 0).clamp(0, 8),
    checked: json['checked'] as bool?,
    spans: (json['spans'] as List<Object?>? ?? const [])
        .map((s) => TextSpanNode.fromJson(s as Map<String, Object?>))
        .toList(),
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

/// A quoted line.
class QuoteBlock extends TextBlock {
  const QuoteBlock({
    required super.id,
    required this.spans,
    super.align,
    super.spaceBefore,
  });

  @override
  final List<TextSpanNode> spans;

  @override
  QuoteBlock withSpans(List<TextSpanNode> spans) => copyWith(spans: spans);

  @override
  QuoteBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      copyWith(align: align, spaceBefore: spaceBefore);

  @override
  QuoteBlock normalized() => super.normalized() as QuoteBlock;

  QuoteBlock copyWith({
    List<TextSpanNode>? spans,
    BlockAlign? align,
    double? spaceBefore,
  }) => QuoteBlock(
    id: id,
    spans: spans ?? this.spans,
    align: align ?? this.align,
    spaceBefore: spaceBefore ?? this.spaceBefore,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._common(),
    'type': 'quote',
    'spans': spans.map((s) => s.toJson()).toList(),
  };

  static QuoteBlock fromJson(Map<String, Object?> json) => QuoteBlock(
    id: json['id'] as String,
    spans: (json['spans'] as List<Object?>? ?? const [])
        .map((s) => TextSpanNode.fromJson(s as Map<String, Object?>))
        .toList(),
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

/// A fenced code block. Plain text: inline formatting has no meaning in code,
/// so this is not a [TextBlock].
class CodeBlock extends Block {
  const CodeBlock({
    required super.id,
    required this.text,
    this.language,
    super.align,
    super.spaceBefore,
  });

  final String text;

  /// The info string after the opening fence, or null for none.
  final String? language;

  @override
  String get plainText => text;

  @override
  CodeBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      copyWith(align: align, spaceBefore: spaceBefore);

  CodeBlock copyWith({
    String? text,
    String? language,
    bool clearLanguage = false,
    BlockAlign? align,
    double? spaceBefore,
  }) => CodeBlock(
    id: id,
    text: text ?? this.text,
    language: clearLanguage ? null : (language ?? this.language),
    align: align ?? this.align,
    spaceBefore: spaceBefore ?? this.spaceBefore,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._common(),
    'type': 'code',
    if (language != null) 'language': language,
    'text': text,
  };

  static CodeBlock fromJson(Map<String, Object?> json) => CodeBlock(
    id: json['id'] as String,
    text: json['text'] as String? ?? '',
    language: json['language'] as String?,
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

/// A horizontal rule.
class DividerBlock extends Block {
  const DividerBlock({required super.id, super.align, super.spaceBefore});

  @override
  String get plainText => '';

  @override
  DividerBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      DividerBlock(
        id: id,
        align: align ?? this.align,
        spaceBefore: spaceBefore ?? this.spaceBefore,
      );

  @override
  Map<String, Object?> toJson() => {..._common(), 'type': 'divider'};

  static DividerBlock fromJson(Map<String, Object?> json) => DividerBlock(
    id: json['id'] as String,
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

class ImageBlock extends Block {
  const ImageBlock({
    required super.id,
    required this.assetId,
    this.caption = '',
    super.align,
    super.spaceBefore,
  });

  /// Names a file in the Knowledge Base's `assets/` folder.
  final String assetId;
  final String caption;

  @override
  String get plainText => caption;

  @override
  ImageBlock copyWithCommon({BlockAlign? align, double? spaceBefore}) =>
      copyWith(align: align, spaceBefore: spaceBefore);

  ImageBlock copyWith({
    String? assetId,
    String? caption,
    BlockAlign? align,
    double? spaceBefore,
  }) => ImageBlock(
    id: id,
    assetId: assetId ?? this.assetId,
    caption: caption ?? this.caption,
    align: align ?? this.align,
    spaceBefore: spaceBefore ?? this.spaceBefore,
  );

  @override
  Map<String, Object?> toJson() => {
    ..._common(),
    'type': 'image',
    'assetId': assetId,
    if (caption.isNotEmpty) 'caption': caption,
  };

  static ImageBlock fromJson(Map<String, Object?> json) => ImageBlock(
    id: json['id'] as String,
    assetId: json['assetId'] as String? ?? '',
    caption: json['caption'] as String? ?? '',
    align: _alignFrom(json['align']),
    spaceBefore: (json['spaceBefore'] as num?)?.toDouble() ?? 0,
  );
}

class BlockDocument {
  const BlockDocument({
    required this.id,
    required this.title,
    required this.blocks,
    this.schemaVersion = kDocumentSchemaVersion,
  });

  final String id;
  final String title;
  final List<Block> blocks;
  final int schemaVersion;

  BlockDocument copyWith({String? title, List<Block>? blocks}) => BlockDocument(
    id: id,
    title: title ?? this.title,
    blocks: blocks ?? this.blocks,
    schemaVersion: schemaVersion,
  );

  /// The canonical form: every text block with its adjacent same-formatting
  /// spans merged.
  ///
  /// Worth caring about because [contentHash] is taken over the JSON, and the
  /// Markdown on disk cannot represent two adjacent spans that share their
  /// formatting — it reads back as one. A document that is not in this form
  /// would hash differently before and after a save, and so look diverged from
  /// the revision it came from.
  BlockDocument normalized() => copyWith(
    blocks: [
      for (final block in blocks)
        if (block is TextBlock) block.normalized() else block,
    ],
  );

  /// Whole-document plain text, used to build the search index.
  String get plainText => blocks.map((b) => b.plainText).join('\n');

  Map<String, Object?> toJson() => {
    'schemaVersion': schemaVersion,
    'id': id,
    'title': title,
    'blocks': blocks.map((b) => b.toJson()).toList(),
  };

  static BlockDocument fromJson(Map<String, Object?> json) => BlockDocument(
    id: json['id'] as String,
    title: json['title'] as String? ?? '',
    blocks: (json['blocks'] as List<Object?>? ?? const [])
        .map((b) => Block.fromJson(b as Map<String, Object?>))
        .toList(),
    schemaVersion:
        (json['schemaVersion'] as num?)?.toInt() ?? kDocumentSchemaVersion,
  );

  /// Canonical JSON text. Documents are written to disk as Markdown; this is
  /// the wire format and what `contentHash` is taken over.
  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  static BlockDocument decode(String source) =>
      fromJson(jsonDecode(source) as Map<String, Object?>);

  /// Stable content hash over the compact encoding, used to detect whether a
  /// local file still matches the revision it was written from.
  String get contentHash =>
      sha256.convert(utf8.encode(jsonEncode(toJson()))).toString();

  static const _eq = DeepCollectionEquality();

  /// Structural equality, so tests and sync checks compare content rather than
  /// object identity.
  bool sameContentAs(BlockDocument other) =>
      _eq.equals(toJson(), other.toJson());
}
