/// A text controller that keeps inline formatting attached to the characters
/// it applies to.
///
/// Flutter's TextEditingController holds plain text, so formatting has to be
/// maintained alongside it. Keeping one format per character — rather than a
/// list of ranges — means an insertion in the middle of a bold word cannot
/// silently detach the formatting that follows it, and it is the same shape the
/// three-way merge works in.
library;

import 'package:diff_match_patch/diff_match_patch.dart' as dmp;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/document_links.dart';
import 'package:dayseven/shared/ui/block_text_style.dart';
import 'package:dayseven/shared/ui/theme.dart';

class RichTextController extends TextEditingController {
  RichTextController({
    List<TextSpanNode> spans = const [],
    this.onOpenDocumentLink,
  }) : _formats = _explode(spans),
       super(text: _displayText(spans));

  static const _documentToken = '\uFFFC';

  final ValueChanged<String>? onOpenDocumentLink;

  List<Format> _formats;

  /// An explicit style chosen at a collapsed caret. Unlike the formats in
  /// [_formats], this belongs to text that has not been inserted yet.
  Format? _typingFormat;

  static String _displayText(List<TextSpanNode> spans) => spans
      .map((span) => isDocumentLinkHref(span.href) ? _documentToken : span.text)
      .join();

  static List<Format> _explode(List<TextSpanNode> spans) => [
    for (final span in spans)
      if (isDocumentLinkHref(span.href))
        span
      else
        for (var i = 0; i < span.text.length; i++) span,
  ];

  /// The current content as document spans, with adjacent like-formatted runs
  /// merged so the saved JSON stays compact.
  List<TextSpanNode> toSpans() {
    final out = <TextSpanNode>[];
    final buffer = StringBuffer();
    Format? current;

    void flush() {
      if (current != null && buffer.isNotEmpty) {
        out.add(current.copyWith(text: buffer.toString()));
      }
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final format = i < _formats.length ? _formats[i] : kPlainFormat;
      if (text[i] == _documentToken && isDocumentLinkHref(format.href)) {
        flush();
        current = null;
        out.add(format);
        continue;
      }
      if (current == null || !current.sameFormatting(format)) {
        flush();
        current = format;
      }
      buffer.write(text[i]);
    }
    flush();
    return out;
  }

  /// Replaces the content wholesale, e.g. when the open document changes under
  /// the editor after a proposal is approved.
  void setSpans(List<TextSpanNode> spans) {
    _formats = _explode(spans);
    _typingFormat = null;
    super.value = TextEditingValue(
      text: _displayText(spans),
      selection: const TextSelection.collapsed(offset: 0),
    );
  }

  /// Replaces the current selection with one atomic, portable page link.
  void insertDocumentLink({required String label, required String href}) {
    final selection = this.selection.isValid
        ? this.selection
        : TextSelection.collapsed(offset: text.length);
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(start, text.length);
    final nextText = text.replaceRange(start, end, _documentToken);
    _formats = [
      ..._formats.take(start),
      TextSpanNode(text: label, href: href),
      ..._formats.skip(end),
    ];
    _typingFormat = null;
    super.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
    );
  }

  /// Replaces [selection], or the controller's current selection, with plain
  /// text while preserving the formatting inheritance used by normal typing.
  void replaceSelection(String replacement, {TextSelection? selection}) {
    final target = selection?.isValid ?? false
        ? selection!
        : this.selection.isValid
        ? this.selection
        : TextSelection.collapsed(offset: text.length);
    final start = target.start.clamp(0, text.length);
    final end = target.end.clamp(start, text.length);

    value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
  }

  @override
  set value(TextEditingValue newValue) {
    if (newValue.text != text) {
      _formats = _reflow(
        text,
        newValue.text,
        _formats,
        insertedFormat: _typingFormat,
      );
    } else if (newValue.selection != selection) {
      // A click, arrow key or selection change starts a new typing context.
      // The effective style will be read from the text beside the new caret.
      _typingFormat = null;
    }
    super.value = newValue;
  }

  /// Carries formatting across an edit. Surviving characters keep their own
  /// format; inserted characters inherit from the character to their left,
  /// which is what makes typing at the end of a bold word stay bold.
  static List<Format> _reflow(
    String oldText,
    String newText,
    List<Format> oldFormats, {
    Format? insertedFormat,
  }) {
    final diffs = dmp.diff(oldText, newText);
    final out = <Format>[];
    var oldIndex = 0;

    for (final d in diffs) {
      switch (d.operation) {
        case dmp.DIFF_EQUAL:
          for (var i = 0; i < d.text.length; i++) {
            out.add(
              oldIndex < oldFormats.length
                  ? oldFormats[oldIndex]
                  : kPlainFormat,
            );
            oldIndex++;
          }
        case dmp.DIFF_DELETE:
          oldIndex += d.text.length;
        case dmp.DIFF_INSERT:
          var inherited =
              insertedFormat ??
              (out.isNotEmpty
                  ? out.last
                  : (oldIndex < oldFormats.length
                        ? oldFormats[oldIndex]
                        : kPlainFormat));
          if (isDocumentLinkHref(inherited.href)) {
            inherited = inherited.copyWith(text: '', href: (_) => null);
          }
          for (var i = 0; i < d.text.length; i++) {
            out.add(inherited);
          }
      }
    }
    return out;
  }

  /// Applies [transform] to every character in [range].
  void applyToRange(TextRange range, Format Function(Format) transform) {
    if (!range.isValid || range.isCollapsed) return;
    final end = range.end.clamp(0, _formats.length);
    for (var i = range.start.clamp(0, _formats.length); i < end; i++) {
      _formats[i] = transform(_formats[i]);
    }
    notifyListeners();
  }

  /// The formatting of the character at [offset], or null past the end. Lets a
  /// caller read what is already there — the link a selection sits inside, say
  /// — rather than only ask yes-or-no questions about it.
  Format? formatAt(int offset) =>
      offset >= 0 && offset < _formats.length ? _formats[offset] : null;

  /// The style newly inserted characters will receive at [offset].
  ///
  /// An explicit toolbar/shortcut choice wins. Otherwise this mirrors
  /// [_reflow]'s natural inheritance: the character to the left, then the one
  /// to the right at the start of a block, then plain text.
  Format formatForTypingAt(int offset) {
    if (_typingFormat case final format?) return format;
    final caret = offset.clamp(0, _formats.length);
    if (caret > 0) return _formats[caret - 1];
    if (_formats.isNotEmpty) return _formats.first;
    return kPlainFormat;
  }

  /// Overrides the style inherited by future insertions at the current caret.
  void setTypingFormat(Format format) {
    final normalized = format.copyWith(text: '');
    if (_typingFormat?.sameFormatting(normalized) ?? false) return;
    _typingFormat = normalized;
    notifyListeners();
  }

  /// Exposed so splitting a block can carry an intentional typing style into
  /// the newly created block.
  Format? get explicitTypingFormat => _typingFormat;

  /// Whether [format] is active throughout [selection], or for text typed at a
  /// collapsed caret. This is the single query path used by editor chrome.
  bool isFormatActive(EditingFormat format, TextSelection selection) {
    if (!selection.isValid) return false;
    if (selection.isCollapsed) {
      return _formatIsOn(format, formatForTypingAt(selection.extentOffset));
    }

    final range = TextRange(start: selection.start, end: selection.end);
    return rangeSatisfies(range, (value) => _formatIsOn(format, value));
  }

  /// Toggles [format] for the selected characters or for text typed next at a
  /// collapsed caret.
  void toggleFormat(EditingFormat format, TextSelection selection) {
    if (!selection.isValid) return;

    if (selection.isCollapsed) {
      final current = formatForTypingAt(selection.extentOffset);
      setTypingFormat(
        _setFormat(format, current, !_formatIsOn(format, current)),
      );
      return;
    }

    final range = TextRange(start: selection.start, end: selection.end);
    final turnOn = !rangeSatisfies(
      range,
      (value) => _formatIsOn(format, value),
    );
    applyToRange(range, (value) => _setFormat(format, value, turnOn));
  }

  /// True when every character in [range] already satisfies [test], which is
  /// what makes a formatting shortcut toggle rather than only ever set.
  bool rangeSatisfies(TextRange range, bool Function(Format) test) {
    if (!range.isValid || range.isCollapsed) return false;
    final end = range.end.clamp(0, _formats.length);
    for (var i = range.start.clamp(0, _formats.length); i < end; i++) {
      if (!test(_formats[i])) return false;
    }
    return true;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? const TextStyle();
    final colors = context.ds;
    final linkColor = colors.link;
    final children = <InlineSpan>[];
    final buffer = StringBuffer();
    Format? current;

    void flush() {
      if (current != null && buffer.isNotEmpty) {
        children.add(
          TextSpan(
            text: buffer.toString(),
            style: styleFor(current, base, linkColor: linkColor),
          ),
        );
      }
      buffer.clear();
    }

    for (var i = 0; i < text.length; i++) {
      final format = i < _formats.length ? _formats[i] : kPlainFormat;
      if (text[i] == _documentToken && isDocumentLinkHref(format.href)) {
        flush();
        current = null;
        final tokenOffset = i;
        final documentStyle = styleFor(
          format.copyWith(href: (_) => null),
          base,
        ).copyWith(color: colors.documentLink, decoration: TextDecoration.none);
        children.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Semantics(
              link: true,
              label: format.text,
              child: GestureDetector(
                key: ValueKey('document-link-${format.href}'),
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  final keyboard = HardwareKeyboard.instance;
                  final follows = defaultTargetPlatform == TargetPlatform.macOS
                      ? keyboard.isMetaPressed
                      : keyboard.isControlPressed;
                  if (follows) {
                    onOpenDocumentLink?.call(format.href!);
                  } else {
                    selection = TextSelection(
                      baseOffset: tokenOffset,
                      extentOffset: tokenOffset + 1,
                    );
                  }
                },
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.description_outlined,
                        size: base.fontSize ?? 15,
                        color: colors.documentLink,
                      ),
                      const SizedBox(width: 3),
                      Text(format.text, style: documentStyle),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      if (current == null || !current.sameFormatting(format)) {
        flush();
        current = format;
      }
      buffer.write(text[i]);
    }
    flush();

    return TextSpan(style: base, children: children);
  }
}

bool _formatIsOn(EditingFormat format, Format value) => switch (format) {
  EditingFormat.bold => value.bold,
  EditingFormat.italic => value.italic,
  EditingFormat.strikethrough => value.strikethrough,
  EditingFormat.underline => value.underline,
};

Format _setFormat(EditingFormat format, Format value, bool enabled) =>
    switch (format) {
      EditingFormat.bold => value.copyWith(bold: enabled),
      EditingFormat.italic => value.copyWith(italic: enabled),
      EditingFormat.strikethrough => value.copyWith(strikethrough: enabled),
      EditingFormat.underline => value.copyWith(underline: enabled),
    };

/// The colours offered for text and highlight. A small fixed set rather than a
/// colour picker, to keep the editor's surface area to what is specified.
const List<String> kTextColors = [
  '#1D2025',
  '#8A3B12',
  '#1C5B3A',
  '#123B8A',
  '#6B2D6B',
  '#8A1220',
];

const List<String> kHighlightColors = [
  '#F2E7C9',
  '#DCEBDA',
  '#D9E4F2',
  '#EFDCE8',
  '#E7E7E7',
];
