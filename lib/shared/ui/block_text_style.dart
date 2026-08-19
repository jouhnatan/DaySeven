/// Rendering inline document formatting as Flutter text styles.
///
/// Kept apart from the editor because more than the editor draws formatted
/// spans: the diff view renders the same document model read-only, and pulling
/// in the whole editing controller for one style function would tie the two
/// features together.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/blocks/blocks.dart';

/// A zero-length span carrying only formatting.
typedef Format = TextSpanNode;

const Format kPlainFormat = TextSpanNode(text: '');

/// Turns a document span's formatting into a Flutter style.
TextStyle styleFor(TextSpanNode format, TextStyle base) {
  final decorations = <TextDecoration>[
    if (format.underline) TextDecoration.underline,
    if (format.strikethrough) TextDecoration.lineThrough,
  ];

  return base.copyWith(
    fontFamily: format.font ?? base.fontFamily,
    fontWeight: format.bold ? FontWeight.w700 : base.fontWeight,
    fontVariations: [FontVariation('wght', format.bold ? 700 : 400)],
    fontStyle: format.italic ? FontStyle.italic : FontStyle.normal,
    decoration: decorations.isEmpty
        ? TextDecoration.none
        : TextDecoration.combine(decorations),
    decorationColor: parseColor(format.color) ?? base.color,
    color: parseColor(format.color) ?? base.color,
    backgroundColor: parseColor(format.highlight),
  );
}

/// Parses `#RRGGBB`. Returns null for null or malformed input rather than
/// throwing, so a hand-edited document cannot crash the editor.
Color? parseColor(String? hex) {
  if (hex == null) return null;
  final cleaned = hex.replaceFirst('#', '').trim();
  if (cleaned.length != 6) return null;
  final value = int.tryParse(cleaned, radix: 16);
  return value == null ? null : Color(0xFF000000 | value);
}
