/// The DaySeven document model.
///
/// One paragraph is one block, Notion-style. Blocks carry stable ids so that a
/// three-way merge can align them by identity rather than by position: a
/// paragraph that moved is the same paragraph, not a delete plus an insert.
///
/// This exact JSON is what is written to disk as a `.d7doc`, what is stored in
/// `revisions.content`, and what the diff view compares. Pure Dart — nothing in
/// this file may import Flutter or Supabase.
library;

import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';

/// Bumped when the on-disk shape changes in a way that needs migration.
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

  bool get isEmpty => text.isEmpty;

  /// True when two spans differ only in their text, and so can be concatenated.
  bool sameFormatting(TextSpanNode other) =>
      bold == other.bold &&
      italic == other.italic &&
      strikethrough == other.strikethrough &&
      underline == other.underline &&
      color == other.color &&
      highlight == other.highlight &&
      font == other.font;

  TextSpanNode copyWith({String? text}) => TextSpanNode(
    text: text ?? this.text,
    bold: bold,
    italic: italic,
    strikethrough: strikethrough,
    underline: underline,
    color: color,
    highlight: highlight,
    font: font,
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

  static Block fromJson(Map<String, Object?> json) {
    final type = json['type'] as String?;
    return switch (type) {
      'image' => ImageBlock.fromJson(json),
      _ => ParagraphBlock.fromJson(json),
    };
  }

  Map<String, Object?> _common() => {
    'id': id,
    if (align != BlockAlign.left) 'align': align.name,
    if (spaceBefore != 0) 'spaceBefore': spaceBefore,
  };
}

class ParagraphBlock extends Block {
  const ParagraphBlock({
    required super.id,
    required this.spans,
    super.align,
    super.spaceBefore,
  });

  final List<TextSpanNode> spans;

  @override
  String get plainText => spans.map((s) => s.text).join();

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

  /// Merges adjacent spans that share formatting and drops empty ones, so that
  /// two documents with the same appearance also have the same JSON.
  ParagraphBlock normalized() {
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
    return copyWith(spans: out);
  }

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

  /// Canonical JSON text: what is written to the `.d7doc` file.
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
