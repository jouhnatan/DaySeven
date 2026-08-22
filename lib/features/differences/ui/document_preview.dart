/// Read-only block rendering used by proposal paper previews.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/block_text_style.dart';
import 'package:dayseven/shared/ui/theme.dart';

class ProposedDocumentPreview extends StatelessWidget {
  const ProposedDocumentPreview({
    super.key,
    required this.document,
    this.compact = true,
  });

  final BlockDocument document;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            document.title.isEmpty ? 'Untitled' : document.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: editorTextStyle(
              size: compact ? 24 : 28,
              weight: 600,
              color: colors.text,
            ),
          ),
          const SizedBox(height: 18),
          for (final block in document.blocks)
            Padding(
              padding: EdgeInsets.only(
                bottom: compact ? 9 : 12,
                top: block.spaceBefore,
              ),
              child: _PreviewBlock(block: block, compact: compact),
            ),
        ],
      ),
    );
  }
}

class _PreviewBlock extends StatelessWidget {
  const _PreviewBlock({required this.block, required this.compact});

  final Block block;
  final bool compact;

  TextAlign get _textAlign => switch (block.align) {
    BlockAlign.left => TextAlign.left,
    BlockAlign.center => TextAlign.center,
    BlockAlign.right => TextAlign.right,
  };

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    Widget content;
    switch (block) {
      case final HeadingBlock heading:
        content = _richText(
          heading,
          headingStyle(heading.level, colors.text),
          colors.link,
        );
      case final ListItemBlock item:
        final marker = item.checked == null
            ? item.style == ListStyle.ordered
                  ? '1.'
                  : '•'
            : item.checked!
            ? '☑'
            : '☐';
        content = Padding(
          padding: EdgeInsets.only(left: item.depth * 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 22, child: Text(marker)),
              Expanded(
                child: _richText(
                  item,
                  editorTextStyle(size: 14, height: 1.5, color: colors.text),
                  colors.link,
                ),
              ),
            ],
          ),
        );
      case final QuoteBlock quote:
        content = Container(
          padding: const EdgeInsets.only(left: 12),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: colors.muted, width: 2)),
          ),
          child: _richText(
            quote,
            editorTextStyle(
              size: 14,
              height: 1.5,
              italic: true,
              color: colors.text,
            ),
            colors.link,
          ),
        );
      case final TextBlock text:
        content = _richText(
          text,
          editorTextStyle(size: 14, height: 1.5, color: colors.text),
          colors.link,
        );
      case final CodeBlock code:
        content = Container(
          padding: const EdgeInsets.all(10),
          color: colors.selection,
          child: Text(
            code.text,
            style: editorTextStyle(
              size: 12,
              height: 1.45,
              color: colors.text,
            ).copyWith(fontFamily: 'Courier New'),
          ),
        );
      case DividerBlock():
        content = Divider(color: colors.border);
      case final TableBlock table:
        content = Table(
          border: TableBorder.all(color: colors.border, width: .7),
          children: [
            for (final row in table.rows)
              TableRow(
                children: [
                  for (final cell in row)
                    Padding(
                      padding: const EdgeInsets.all(5),
                      child: Text(
                        cell.map((span) => span.text).join(),
                        style: editorTextStyle(size: 11, color: colors.text),
                      ),
                    ),
                ],
              ),
          ],
        );
      case final ImageBlock image:
        content = Container(
          height: compact ? 72 : 100,
          alignment: Alignment.center,
          color: colors.selection,
          padding: const EdgeInsets.all(8),
          child: Text(
            image.caption.isEmpty ? 'Image' : image.caption,
            textAlign: TextAlign.center,
            style: editorTextStyle(size: 12, italic: true, color: colors.muted),
          ),
        );
    }
    return Align(
      alignment: switch (block.align) {
        BlockAlign.left => Alignment.centerLeft,
        BlockAlign.center => Alignment.center,
        BlockAlign.right => Alignment.centerRight,
      },
      child: content,
    );
  }

  Widget _richText(TextBlock block, TextStyle base, Color linkColor) =>
      Text.rich(
        TextSpan(
          children: [
            for (final span in block.spans)
              TextSpan(
                text: span.text,
                style: styleFor(span, base, linkColor: linkColor),
              ),
          ],
        ),
        textAlign: _textAlign,
      );
}
