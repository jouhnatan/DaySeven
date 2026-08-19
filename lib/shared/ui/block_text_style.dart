/// Rendering inline document formatting as Flutter text styles.
///
/// Kept apart from the editor because more than the editor draws formatted
/// spans: the diff view renders the same document model read-only, and pulling
/// in the whole editing controller for one style function would tie the two
/// features together.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// A zero-length span carrying only formatting.
typedef Format = TextSpanNode;

const Format kPlainFormat = TextSpanNode(text: '');

/// The base style for a heading of [level].
///
/// Here rather than in the editor for the reason this file exists: the diff
/// view draws the same headings read-only and must not pull in the editing
/// controller to do it.
TextStyle headingStyle(int level, Color color) => aleo(
  size: switch (level) {
    1 => 26,
    2 => 22,
    3 => 19,
    4 => 17,
    5 => 15,
    _ => 14,
  },
  weight: 600,
  height: 1.3,
  color: color,
);

/// Turns a document span's formatting into a Flutter style.
///
/// [linkColor] is what a link is drawn in; pass null where links should read as
/// ordinary text. A span that sets its own colour keeps it — an explicit choice
/// outranks the default.
TextStyle styleFor(TextSpanNode format, TextStyle base, {Color? linkColor}) {
  final isLink = format.href != null && linkColor != null;
  // A reference is a marker, not prose: smaller, lifted, and in the link
  // colour so it reads as something to follow.
  final isFootnote = format.footnote != null;
  final decorations = <TextDecoration>[
    if (format.underline || isLink) TextDecoration.underline,
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
    decorationColor:
        parseColor(format.color) ?? (isLink ? linkColor : null) ?? base.color,
    color:
        parseColor(format.color) ??
        (isLink || isFootnote ? linkColor : null) ??
        base.color,
    backgroundColor: parseColor(format.highlight),
    fontSize: isFootnote ? (base.fontSize ?? 14) * 0.75 : base.fontSize,
    fontFeatures: isFootnote ? const [FontFeature.superscripts()] : null,
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
