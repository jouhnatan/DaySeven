/// Markdown as DaySeven's on-disk format.
///
/// A document is a Markdown file that any editor can open. What Markdown cannot
/// express is handled two different ways, and the split is deliberate:
///
///  * **Inline** formatting Markdown lacks — underline, colour, highlight, font
///    — becomes inline HTML (`<u>`, `<span style="…">`). Inline HTML is parsed
///    inside a paragraph, so these render correctly in other editors.
///  * **Block-level** attributes — alignment, space-before — go in the block's
///    `d7` comment, *not* an HTML wrapper. A block starting with `<p` is a raw
///    HTML block under CommonMark, and Markdown inside one is not parsed, so
///    `<p align="center">a **bold** word</p>` renders with literal asterisks.
///    Keeping alignment out of the body is what lets bold keep working.
///
/// The `d7` comment also carries the block's id, which the three-way merge needs
/// to tell "this paragraph moved" from "deleted, then inserted".
///
/// The writer is total: every [BlockDocument] has exactly one encoding. So the
/// reader only has to accept that grammar, plus a fallback for hand-edited
/// files — anything it does not recognise becomes a paragraph, mirroring how
/// `Block.fromJson` treats an unknown block type.
///
/// Pure Dart — nothing in this file may import Flutter or Supabase.
library;

import 'dart:convert';

import 'package:uuid/uuid.dart';

import 'package:dayseven/shared/blocks/blocks.dart';

/// Bumped when the *file* format changes. Separate from
/// `kDocumentSchemaVersion`, which tracks the JSON model that goes to the
/// server; the two move independently.
const int kMarkdownFormatVersion = 1;

/// Where image assets live, relative to the Knowledge Base root. Cosmetic only:
/// the reader takes just the file name, so a document can be moved between
/// folders without rewriting its contents.
const String _assetDirectory = '.settings/assets';

const Uuid _uuid = Uuid();

// ------------------------------------------------------------------ encode --

String encodeMarkdown(BlockDocument document) {
  final out = StringBuffer()
    ..writeln('---')
    ..writeln('d7: $kMarkdownFormatVersion')
    ..writeln('schema: ${document.schemaVersion}')
    ..writeln('id: ${jsonEncode(document.id)}')
    ..writeln('title: ${jsonEncode(document.title)}')
    ..writeln('---');

  for (final block in document.blocks) {
    out
      ..writeln()
      ..writeln(_encodeComment(block))
      ..writeln(_encodeBody(block));
  }

  // Exactly one trailing newline, so the file ends the way text files do.
  return '${out.toString().trimRight()}\n';
}

/// Where a block's body begins in the encoded Markdown, in UTF-16 units.
///
/// Awareness needs this. A caret lives at an offset inside one block's text
/// box, but the CRDT holds each file as a single `Y.Text` of the whole
/// Markdown, so a block-relative offset has to be turned into a file-relative
/// one before it can be anchored.
///
/// Locating the block by its own marker comment rather than by re-encoding the
/// preceding blocks keeps this correct when block encodings change: the marker
/// is the one part of the format that is guaranteed to be present, unique, and
/// immediately followed by the body.
///
/// Returns null when the block is not in this Markdown — a document and an
/// editor can disagree for a moment after an external edit, and a caret drawn
/// from a stale mapping is worse than no caret.
int? markdownBodyOffsetOfBlock(String markdown, String blockId) {
  // The trailing space matters: block ids are not prefix-free, so searching
  // for `<!-- d7 p-1` also finds `<!-- d7 p-10`. Every marker has a space
  // after the id, before either its attributes or the closing `-->`.
  final marker = markdown.indexOf('<!-- d7 $blockId ');
  if (marker < 0) return null;
  final endOfComment = markdown.indexOf('\n', marker);
  if (endOfComment < 0) return null;
  return endOfComment + 1;
}

/// `<!-- d7 <id> align=center space=16 width=0.5 -->`, carrying what the body
/// cannot. `width` is the image's fraction of the editor content width.
String _encodeComment(Block block) {
  final out = StringBuffer('<!-- d7 ${block.id}');
  if (block.align != BlockAlign.left) out.write(' align=${block.align.name}');
  if (block.spaceBefore != 0) out.write(' space=${_number(block.spaceBefore)}');
  if (block is ImageBlock && block.widthFraction != null) {
    out.write(' width=${_number(block.widthFraction!)}');
  }
  return (out..write(' -->')).toString();
}

/// Deterministic, or `encode(decode(md)) == md` fails on whole numbers.
String _number(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// Text blocks are normalized on the way out: two adjacent spans with the same
/// formatting are indistinguishable once written, so the encoder emits the
/// canonical form rather than one the reader could never reproduce.
String _encodeBody(Block block) => switch (block) {
  HeadingBlock() =>
    '${'#' * block.level} ${_encodeSpans(block.normalized().spans)}',
  ListItemBlock() => _encodeListItem(block.normalized()),
  QuoteBlock() => '> ${_encodeSpans(block.normalized().spans)}',
  ParagraphBlock() => _encodeSpans(block.normalized().spans),
  CodeBlock() => _encodeCode(block),
  DividerBlock() => '---',
  TableBlock() => _encodeTable(block.normalized()),
  FootnoteBlock() =>
    '[^${block.label}]: ${_encodeSpans(block.normalized().spans)}',
  ImageBlock() =>
    '![${_escapeCaption(block.caption)}](${block.isExternal ? _escapeUrl(block.url!) : '$_assetDirectory/${block.assetId}'})',
};

String _encodeTable(TableBlock block) {
  final columns = block.columnCount;
  if (columns == 0 || block.rows.isEmpty) return '';

  String row(List<List<TextSpanNode>> cells) {
    final out = [
      for (var c = 0; c < columns; c++)
        c < cells.length ? _encodeCell(cells[c]) : '',
    ];
    return '| ${out.join(' | ')} |';
  }

  final rule = [
    for (var c = 0; c < columns; c++)
      switch (block.alignOf(c)) {
        BlockAlign.center => ':---:',
        BlockAlign.right => '---:',
        BlockAlign.left => '---',
      },
  ];

  return [
    row(block.rows.first),
    '| ${rule.join(' | ')} |',
    for (final r in block.rows.skip(1)) row(r),
  ].join('\n');
}

/// A cell is inline content on one line, so a pipe has to be escaped and a
/// newline cannot survive as one.
String _encodeCell(List<TextSpanNode> spans) => _encodeSpans([
  for (final span in spans)
    span.copyWith(text: span.text.replaceAll('\n', ' ')),
]).replaceAll('|', r'\|');

String _encodeListItem(ListItemBlock block) {
  // Ordered items are always written `1.`; every renderer numbers them by
  // position, and a fixed marker keeps the output byte-stable.
  final marker = block.style == ListStyle.ordered ? '1.' : '-';
  final box = switch (block.checked) {
    null => '',
    true => '[x] ',
    false => '[ ] ',
  };
  return '${'  ' * block.depth}$marker $box${_encodeSpans(block.spans)}';
}

String _encodeCode(CodeBlock block) {
  // A fence long enough to survive backticks in the code itself.
  var fence = '```';
  while (block.text.contains(fence)) {
    fence += '`';
  }
  return '$fence${block.language ?? ''}\n${block.text}\n$fence';
}

String _encodeSpans(List<TextSpanNode> spans) {
  final out = StringBuffer();
  for (var i = 0; i < spans.length; i++) {
    out.write(_encodeSpan(spans[i], firstInBlock: i == 0));
  }
  return out.toString();
}

String _encodeSpan(TextSpanNode span, {required bool firstInBlock}) {
  if (span.text.isEmpty) return '';

  var out = _escapeText(span.text, firstInBlock: firstInBlock);

  // A reference is written as its marker, not its text, so the file reads the
  // way a Markdown footnote is supposed to.
  if (span.footnote != null) return '[^${span.footnote}]';

  // Innermost, so `**[text](url)**` rather than `[**text**](url)`; both read
  // back the same, and this keeps one shape.
  if (span.href != null) out = '[$out](${_escapeUrl(span.href!)})';

  // `**text**` and `_text_` only work when the delimiters hug non-space
  // characters, and the character-per-format controller routinely produces
  // whitespace-only spans. The HTML forms have no such rule.
  final hugs = span.text.trim() == span.text;

  if (span.strikethrough) out = hugs ? '~~$out~~' : '<del>$out</del>';
  if (span.italic) out = hugs ? '_${out}_' : '<em>$out</em>';
  if (span.bold) out = hugs ? '**$out**' : '<strong>$out</strong>';
  if (span.underline) out = '<u>$out</u>';

  final style = _encodeStyle(span);
  if (style != null) out = '<span style="$style">$out</span>';

  return out;
}

/// One span carries all three style-driven attributes, in a fixed order so the
/// output is byte-stable.
String? _encodeStyle(TextSpanNode span) {
  final parts = <String>[
    if (span.font != null) 'font-family:${span.font}',
    if (span.color != null) 'color:${span.color}',
    if (span.highlight != null) 'background:${span.highlight}',
  ];
  return parts.isEmpty ? null : parts.join(';');
}

/// Escapes everything that would otherwise be read back as markup.
///
/// [firstInBlock] additionally escapes the characters that are only meaningful
/// at the start of a line, so a paragraph that reads `# Not a heading` survives
/// as text. Over-escaping is harmless — `\#` renders as `#` anywhere — so the
/// test is on the span rather than the final column, which markers would shift.
String _escapeText(String text, {required bool firstInBlock}) {
  var out = text
      .replaceAll(r'\', r'\\')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('*', r'\*')
      .replaceAll('_', r'\_')
      .replaceAll('~', r'\~')
      .replaceAll('`', r'\`')
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');

  // Every line of the output is a line start, not just the block's first, or a
  // paragraph reading "a<newline>- b" would come back as a list.
  final lines = out.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (i > 0 || firstInBlock) lines[i] = _escapeLineStart(lines[i]);
  }

  // A newline inside a span becomes CommonMark's hard line break. The escaping
  // above has already doubled any real backslash, so the trailing one here is
  // unambiguous.
  return lines.join('\\\n');
}

final RegExp _lineStartActive = RegExp(r'^([#>+=|-]|\d+[.)])');

String _escapeLineStart(String text) =>
    _lineStartActive.hasMatch(text) ? '\\$text' : text;

String _escapeUrl(String url) =>
    url.replaceAll('(', '%28').replaceAll(')', '%29').replaceAll(' ', '%20');

/// Captions sit inside `![…]`, so brackets and parentheses matter; nothing is
/// at a line start.
String _escapeCaption(String caption) => caption
    .replaceAll(r'\', r'\\')
    .replaceAll('[', r'\[')
    .replaceAll(']', r'\]')
    .replaceAll('(', r'\(')
    .replaceAll(')', r'\)')
    .replaceAll('\n', ' ');

// ------------------------------------------------------------------ decode --

BlockDocument decodeMarkdown(String source) {
  final lines = const LineSplitter().convert(source);
  var i = 0;

  final front = <String, Object?>{};
  if (lines.isNotEmpty && lines.first.trimRight() == '---') {
    i = 1;
    while (i < lines.length && lines[i].trimRight() != '---') {
      final at = lines[i].indexOf(':');
      if (at > 0) {
        front[lines[i].substring(0, at).trim()] = _frontValue(
          lines[i].substring(at + 1).trim(),
        );
      }
      i++;
    }
    if (i < lines.length) i++; // the closing fence
  }

  final blocks = <Block>[];
  while (i < lines.length) {
    if (lines[i].trim().isEmpty) {
      i++;
      continue;
    }

    var attributes = const <String, String>{};
    final comment = _commentPattern.firstMatch(lines[i].trim());
    if (comment != null) {
      attributes = _parseAttributes(comment.group(1)!);
      i++;
    }

    // A fenced block runs to its closing fence, blank lines and all; anything
    // else ends at the next blank line or block comment.
    final body = <String>[];
    // A comment can be the last line in the file — an empty final paragraph.
    final fence = i < lines.length ? _fencePattern.firstMatch(lines[i]) : null;
    if (fence != null) {
      body.add(lines[i]);
      i++;
      while (i < lines.length &&
          !lines[i].trimRight().startsWith(fence.group(1)!)) {
        body.add(lines[i]);
        i++;
      }
      if (i < lines.length) {
        body.add(lines[i]);
        i++;
      }
    } else if (i < lines.length && _tableRowPattern.hasMatch(lines[i])) {
      while (i < lines.length && _tableRowPattern.hasMatch(lines[i])) {
        body.add(lines[i]);
        i++;
      }
    } else {
      while (i < lines.length &&
          lines[i].trim().isNotEmpty &&
          !_commentPattern.hasMatch(lines[i].trim()) &&
          (body.isEmpty || !_startsBlock(lines[i]))) {
        body.add(lines[i]);
        i++;
      }
    }

    blocks.add(_decodeBlock(attributes, body));
  }

  return BlockDocument(
    id: front['id'] as String? ?? _uuid.v7(),
    title: front['title'] as String? ?? '',
    blocks: blocks,
    schemaVersion: (front['schema'] as num?)?.toInt() ?? kDocumentSchemaVersion,
  );
}

Object? _frontValue(String raw) {
  try {
    return jsonDecode(raw);
  } on FormatException {
    return raw; // hand-written and unquoted; take it as written
  }
}

final RegExp _commentPattern = RegExp(r'^<!--\s*d7\s+(.*?)\s*-->$');
final RegExp _headingPattern = RegExp(r'^(#{1,6})\s+(.*)$', dotAll: true);
final RegExp _imagePattern = RegExp(r'^!\[(.*)\]\((.*)\)$', dotAll: true);
final RegExp _fencePattern = RegExp(r'^(`{3,}|~{3,})(.*)$');

/// True for a line that can only be the start of its own block. Used to split
/// hand-written files, where consecutive lines are not separated by blanks the
/// way this encoder separates them.
bool _startsBlock(String line) =>
    _tableRowPattern.hasMatch(line) ||
    _footnotePattern.hasMatch(line) ||
    _listPattern.hasMatch(line) ||
    _quotePattern.hasMatch(line) ||
    _headingPattern.hasMatch(line) ||
    _dividerPattern.hasMatch(line) ||
    _fencePattern.hasMatch(line);
final RegExp _dividerPattern = RegExp(r'^\s*(-{3,}|\*{3,}|_{3,})\s*$');
final RegExp _tableRowPattern = RegExp(r'^\s*\|.*\|\s*$');
final RegExp _tableRulePattern = RegExp(r'^\s*\|[\s:|-]+\|\s*$');
final RegExp _footnotePattern = RegExp(
  r'^\[\^([^\]]+)\]:\s*(.*)$',
  dotAll: true,
);
final RegExp _footnoteRefPattern = RegExp(r'^\[\^([^\]]+)\]');

/// A scheme or an absolute path means the image is not in the bundle.
final RegExp _externalUrlPattern = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.-]*:|/)');
final RegExp _quotePattern = RegExp(r'^>\s?(.*)$', dotAll: true);
final RegExp _listPattern = RegExp(
  r'^([ \t]*)([-*+]|\d+[.)])\s+(\[([ xX])\]\s+)?(.*)$',
  dotAll: true,
);

Map<String, String> _parseAttributes(String raw) {
  final parts = raw.split(RegExp(r'\s+'));
  if (parts.isEmpty) return const {};

  final out = <String, String>{'id': parts.first};
  for (final part in parts.skip(1)) {
    final at = part.indexOf('=');
    if (at > 0) out[part.substring(0, at)] = part.substring(at + 1);
  }
  return out;
}

double? _decodeWidthFraction(Map<String, String> attributes) {
  final raw = attributes['width'];
  if (raw == null) return null;
  final v = double.tryParse(raw);
  if (v == null || !v.isFinite) return null;
  if (v < kImageMinFraction || v > kImageMaxFraction) {
    return v.clamp(kImageMinFraction, kImageMaxFraction).toDouble();
  }
  // Normalize to two decimals for byte-stable round-trip.
  return double.parse(
    v.clamp(kImageMinFraction, kImageMaxFraction).toStringAsFixed(2),
  );
}

Block _decodeBlock(Map<String, String> attributes, List<String> body) {
  final id = attributes['id'] ?? _uuid.v7();
  final align = switch (attributes['align']) {
    'center' => BlockAlign.center,
    'right' => BlockAlign.right,
    _ => BlockAlign.left,
  };
  final space = double.tryParse(attributes['space'] ?? '') ?? 0;
  final widthFraction = _decodeWidthFraction(attributes);
  final text = _joinBody(body);

  // Fenced code first: its contents must not be read as anything else.
  if (body.isNotEmpty && _fencePattern.hasMatch(body.first)) {
    final info = _fencePattern.firstMatch(body.first)!.group(2)!.trim();
    final closed =
        body.length > 1 && _fencePattern.hasMatch(body.last.trimRight());
    return CodeBlock(
      id: id,
      language: info.isEmpty ? null : info,
      text: body.sublist(1, closed ? body.length - 1 : body.length).join('\n'),
      align: align,
      spaceBefore: space,
    );
  }

  if (body.length == 1 && _dividerPattern.hasMatch(body.first)) {
    return DividerBlock(id: id, align: align, spaceBefore: space);
  }

  if (body.length > 1 && body.every(_tableRowPattern.hasMatch)) {
    return _decodeTable(id, body, align, space);
  }

  final footnote = _footnotePattern.firstMatch(text);
  if (footnote != null) {
    return FootnoteBlock(
      id: id,
      label: footnote.group(1)!,
      spans: decodeInlineSpans(footnote.group(2)!),
      align: align,
      spaceBefore: space,
    );
  }

  final list = _listPattern.firstMatch(text);
  if (list != null) {
    final marker = list.group(2)!;
    final box = list.group(4);
    return ListItemBlock(
      id: id,
      style: marker.endsWith('.') || marker.endsWith(')')
          ? ListStyle.ordered
          : ListStyle.bullet,
      // Two spaces to a level, and a tab counts as one level.
      depth: (list.group(1)!.replaceAll('\t', '  ').length ~/ 2).clamp(0, 8),
      checked: box == null ? null : box.toLowerCase() == 'x',
      spans: decodeInlineSpans(list.group(5)!),
      align: align,
      spaceBefore: space,
    );
  }

  final quote = _quotePattern.firstMatch(text);
  if (quote != null) {
    return QuoteBlock(
      id: id,
      spans: decodeInlineSpans(quote.group(1)!),
      align: align,
      spaceBefore: space,
    );
  }

  final image = _imagePattern.firstMatch(text);
  if (image != null) {
    final url = _unescapeUrl(image.group(2)!);
    final external = _externalUrlPattern.hasMatch(url);
    return ImageBlock(
      id: id,
      // For a bundled image, only the file name: moving a document between
      // folders then never has to rewrite the path.
      assetId: external ? '' : _basename(url),
      url: external ? url : null,
      caption: _unescapeCaption(image.group(1)!),
      widthFraction: widthFraction,
      align: align,
      spaceBefore: space,
    );
  }

  final heading = _headingPattern.firstMatch(text);
  if (heading != null) {
    return HeadingBlock(
      id: id,
      level: heading.group(1)!.length,
      spans: decodeInlineSpans(heading.group(2)!),
      align: align,
      spaceBefore: space,
    );
  }

  return ParagraphBlock(
    id: id,
    spans: decodeInlineSpans(text),
    align: align,
    spaceBefore: space,
  );
}

TableBlock _decodeTable(
  String id,
  List<String> body,
  BlockAlign align,
  double space,
) {
  List<String> cells(String line) {
    final trimmed = line.trim();
    final inner = trimmed.substring(1, trimmed.length - 1);
    final out = <String>[];
    final buffer = StringBuffer();
    for (var i = 0; i < inner.length; i++) {
      if (inner[i] == r'\' && i + 1 < inner.length && inner[i + 1] == '|') {
        buffer.write('|');
        i++;
      } else if (inner[i] == '|') {
        out.add(buffer.toString().trim());
        buffer.clear();
      } else {
        buffer.write(inner[i]);
      }
    }
    out.add(buffer.toString().trim());
    return out;
  }

  final columnAlign = <BlockAlign>[];
  final rows = <List<List<TextSpanNode>>>[];

  for (final line in body) {
    if (_tableRulePattern.hasMatch(line) && rows.length == 1) {
      for (final cell in cells(line)) {
        final left = cell.startsWith(':');
        final right = cell.endsWith(':');
        columnAlign.add(
          right && left
              ? BlockAlign.center
              : right
              ? BlockAlign.right
              : BlockAlign.left,
        );
      }
      continue;
    }
    rows.add([for (final cell in cells(line)) decodeInlineSpans(cell)]);
  }

  return TableBlock(
    id: id,
    rows: rows,
    columnAlign: columnAlign,
    align: align,
    spaceBefore: space,
  );
}

/// Rejoins the lines of one block. A trailing backslash is a hard line break;
/// a plain wrap is treated the same way, so hand-written files keep their shape.
String _joinBody(List<String> body) {
  final out = StringBuffer();
  for (var i = 0; i < body.length; i++) {
    var line = body[i];
    if (i < body.length - 1 && _endsWithHardBreak(line)) {
      line = line.substring(0, line.length - 1);
    }
    out.write(line);
    if (i < body.length - 1) out.write('\n');
  }
  return out.toString();
}

/// True when the line ends in a backslash that is not itself escaped.
bool _endsWithHardBreak(String line) {
  if (!line.endsWith(r'\')) return false;
  var slashes = 0;
  for (var i = line.length - 1; i >= 0 && line[i] == r'\'; i--) {
    slashes++;
  }
  return slashes.isOdd;
}

String _basename(String url) {
  final at = url.lastIndexOf('/');
  return at == -1 ? url : url.substring(at + 1);
}

/// Parses one block's body into spans.
///
/// The HTML tags carry explicit open and close, so they use a stack; the
/// Markdown delimiters toggle, which round-trips exactly because the writer
/// always emits them in balanced pairs.
List<TextSpanNode> decodeInlineSpans(String source) {
  final out = <TextSpanNode>[];
  final buffer = StringBuffer();
  final stack = <TextSpanNode>[];
  var format = const TextSpanNode(text: '');

  void flush() {
    if (buffer.isEmpty) return;
    out.add(format.copyWith(text: buffer.toString()));
    buffer.clear();
  }

  void enter(TextSpanNode next) {
    flush();
    stack.add(format);
    format = next;
  }

  void leave() {
    flush();
    if (stack.isNotEmpty) format = stack.removeLast();
  }

  var i = 0;
  while (i < source.length) {
    final rest = source.substring(i);

    if (source[i] == r'\' && i + 1 < source.length) {
      buffer.write(source[i + 1]);
      i += 2;
      continue;
    }

    final entity = _entityAt(rest);
    if (entity != null) {
      buffer.write(entity.$1);
      i += entity.$2;
      continue;
    }

    if (rest.startsWith('<span style="')) {
      final close = rest.indexOf('">');
      if (close != -1) {
        enter(_withStyle(format, rest.substring(13, close)));
        i += close + 2;
        continue;
      }
    }

    var matched = false;
    for (final (tag, apply) in _htmlTags) {
      if (rest.startsWith('<$tag>')) {
        enter(apply(format));
        i += tag.length + 2;
        matched = true;
        break;
      }
      if (rest.startsWith('</$tag>')) {
        leave();
        i += tag.length + 3;
        matched = true;
        break;
      }
    }
    if (matched) continue;

    if (rest.startsWith('</span>')) {
      leave();
      i += 7;
      continue;
    }

    if (source[i] == '[') {
      final reference = _footnoteRefPattern.matchAsPrefix(rest);
      if (reference != null) {
        flush();
        out.add(
          _withFootnote(format, reference.group(1)!, reference.group(0)!),
        );
        i += reference.group(0)!.length;
        continue;
      }
    }

    // `[label](url)`. An unescaped `[` only ever starts a link, because a
    // literal bracket in the text was escaped on the way out.
    if (source[i] == '[') {
      final link = _linkAt(rest);
      if (link != null) {
        flush();
        // The label is parsed in its own right, then folded onto whatever
        // formatting encloses the link — `**[text](url)**` is bold.
        for (final span in decodeInlineSpans(link.$1)) {
          out.add(_merge(format, span, link.$2));
        }
        i += link.$3;
        continue;
      }
    }

    if (rest.startsWith('**')) {
      flush();
      format = _withBold(format, !format.bold);
      i += 2;
      continue;
    }
    if (rest.startsWith('~~')) {
      flush();
      format = _withStrike(format, !format.strikethrough);
      i += 2;
      continue;
    }
    if (source[i] == '_') {
      flush();
      format = _withItalic(format, !format.italic);
      i += 1;
      continue;
    }

    buffer.write(source[i]);
    i++;
  }

  flush();
  return out;
}

final List<(String, TextSpanNode Function(TextSpanNode))> _htmlTags = [
  ('strong', (f) => _withBold(f, true)),
  ('em', (f) => _withItalic(f, true)),
  ('del', (f) => _withStrike(f, true)),
  ('u', (f) => _withUnderline(f, true)),
];

/// Matches `[label](url)` at the head of [rest], respecting escapes and nested
/// brackets. Returns the label, the url, and how much source it consumed.
(String, String, int)? _linkAt(String rest) {
  var depth = 0;
  var close = -1;
  for (var i = 0; i < rest.length; i++) {
    if (rest[i] == r'\') {
      i++;
      continue;
    }
    if (rest[i] == '[') depth++;
    if (rest[i] == ']') {
      depth--;
      if (depth == 0) {
        close = i;
        break;
      }
    }
  }
  if (close == -1 || close + 1 >= rest.length || rest[close + 1] != '(') {
    return null;
  }

  final end = rest.indexOf(')', close + 2);
  if (end == -1) return null;

  return (
    rest.substring(1, close),
    _unescapeUrl(rest.substring(close + 2, end)),
    end + 1,
  );
}

String _unescapeUrl(String url) =>
    url.replaceAll('%28', '(').replaceAll('%29', ')').replaceAll('%20', ' ');

TextSpanNode _withFootnote(TextSpanNode f, String label, String text) =>
    TextSpanNode(
      text: text,
      bold: f.bold,
      italic: f.italic,
      strikethrough: f.strikethrough,
      underline: f.underline,
      color: f.color,
      highlight: f.highlight,
      font: f.font,
      href: f.href,
      footnote: label,
    );

/// Folds a link label's own formatting onto the formatting around the link.
TextSpanNode _merge(TextSpanNode outer, TextSpanNode inner, String href) =>
    TextSpanNode(
      text: inner.text,
      bold: outer.bold || inner.bold,
      italic: outer.italic || inner.italic,
      strikethrough: outer.strikethrough || inner.strikethrough,
      underline: outer.underline || inner.underline,
      color: inner.color ?? outer.color,
      highlight: inner.highlight ?? outer.highlight,
      font: inner.font ?? outer.font,
      href: href,
    );

/// Returns the decoded character and how many source characters it spanned.
(String, int)? _entityAt(String rest) {
  for (final (entity, value) in const [
    ('&amp;', '&'),
    ('&lt;', '<'),
    ('&gt;', '>'),
    ('&quot;', '"'),
    ('&#39;', "'"),
  ]) {
    if (rest.startsWith(entity)) return (value, entity.length);
  }
  return null;
}

TextSpanNode _withStyle(TextSpanNode f, String style) {
  String? font = f.font;
  String? color = f.color;
  String? highlight = f.highlight;

  for (final property in style.split(';')) {
    final at = property.indexOf(':');
    if (at <= 0) continue;
    final value = property.substring(at + 1).trim();
    switch (property.substring(0, at).trim()) {
      case 'font-family':
        font = value;
      case 'color':
        color = value;
      case 'background':
        highlight = value;
    }
  }

  return TextSpanNode(
    text: '',
    bold: f.bold,
    italic: f.italic,
    strikethrough: f.strikethrough,
    underline: f.underline,
    color: color,
    highlight: highlight,
    font: font,
    href: f.href,
  );
}

TextSpanNode _withBold(TextSpanNode f, bool on) => TextSpanNode(
  text: '',
  bold: on,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
  href: f.href,
);

TextSpanNode _withItalic(TextSpanNode f, bool on) => TextSpanNode(
  text: '',
  bold: f.bold,
  italic: on,
  strikethrough: f.strikethrough,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
  href: f.href,
);

TextSpanNode _withStrike(TextSpanNode f, bool on) => TextSpanNode(
  text: '',
  bold: f.bold,
  italic: f.italic,
  strikethrough: on,
  underline: f.underline,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
  href: f.href,
);

TextSpanNode _withUnderline(TextSpanNode f, bool on) => TextSpanNode(
  text: '',
  bold: f.bold,
  italic: f.italic,
  strikethrough: f.strikethrough,
  underline: on,
  color: f.color,
  highlight: f.highlight,
  font: f.font,
  href: f.href,
);

String _unescapeCaption(String raw) {
  final out = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (raw[i] == r'\' && i + 1 < raw.length) {
      out.write(raw[i + 1]);
      i++;
    } else {
      out.write(raw[i]);
    }
  }
  return out.toString();
}
