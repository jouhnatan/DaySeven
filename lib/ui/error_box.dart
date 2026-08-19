/// How a failure is shown.
///
/// Errors sit in their own rounded panel and can be selected and copied, so
/// what went wrong can be pasted somewhere useful rather than transcribed by
/// hand from a message that has already disappeared.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/app/theme.dart';

class DsErrorBox extends StatelessWidget {
  const DsErrorBox(this.message, {super.key});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.removal,
        borderRadius: const BorderRadius.all(DsRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: SelectableText(
        message,
        style: aleo(size: 12, color: colors.text),
        cursorColor: colors.text,
        // Right-click and the platform's own copy shortcut both work.
        contextMenuBuilder: (context, state) =>
            AdaptiveTextSelectionToolbar.editableText(editableTextState: state),
      ),
    );
  }
}
