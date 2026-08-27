/// How a failure is shown.
///
/// Errors sit in their own rounded panel and can be selected and copied, so
/// what went wrong can be pasted somewhere useful rather than transcribed by
/// hand from a message that has already disappeared.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:dayseven/shared/ui/theme.dart';

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
      // A banner: the wash, a hairline in the matching semantic colour, and
      // ink text. The colour describes the state; it does not shout it.
      decoration: BoxDecoration(
        color: colors.removal,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: colors.danger.withValues(alpha: 0.30)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              message,
              style: DsType.caption(color: colors.text),
              cursorColor: colors.text,
              // Right-click and the platform's own copy shortcut both work.
              contextMenuBuilder: (context, state) =>
                  AdaptiveTextSelectionToolbar.editableText(
                    editableTextState: state,
                  ),
            ),
          ),
          const SizedBox(width: 6),
          DsCopyErrorButton(message: message),
        ],
      ),
    );
  }
}

/// A visible copy affordance for error text.
///
/// Selectable text still supports drag selection and Command/Ctrl+C. This
/// button handles the common case where the useful thing is the whole error,
/// including its database status and diagnostic code.
class DsCopyErrorButton extends StatelessWidget {
  const DsCopyErrorButton({super.key, required this.message, this.size = 28});

  final String message;
  final double size;

  @override
  Widget build(BuildContext context) => IconButton(
    key: const Key('copy-error-message'),
    tooltip: 'Copy error',
    constraints: BoxConstraints.tightFor(width: size, height: size),
    padding: EdgeInsets.zero,
    iconSize: 15,
    color: context.ds.muted,
    onPressed: () => Clipboard.setData(ClipboardData(text: message)),
    icon: const Icon(Icons.copy_outlined),
  );
}
