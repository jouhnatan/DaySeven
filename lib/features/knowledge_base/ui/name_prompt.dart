/// Asks for a single document or folder name.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/dialog.dart';

Future<String?> askForName(
  BuildContext context, {
  required String title,
  String initial = '',
  String actionLabel = 'Create',
}) => showDialog<String>(
  context: context,
  builder: (_) => _NamePromptDialog(
    title: title,
    initial: initial,
    actionLabel: actionLabel,
  ),
);

class _NamePromptDialog extends StatefulWidget {
  const _NamePromptDialog({
    required this.title,
    required this.initial,
    required this.actionLabel,
  });

  final String title;
  final String initial;
  final String actionLabel;

  @override
  State<_NamePromptDialog> createState() => _NamePromptDialogState();
}

class _NamePromptDialogState extends State<_NamePromptDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initial)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.initial.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DsDialog(
      width: 280,
      actions: [
        DsDialogAction(
          label: 'Cancel',
          onPressed: () => Navigator.of(context).pop(),
          tone: DsDialogActionTone.muted,
        ),
        DsDialogAction(
          label: widget.actionLabel,
          onPressed: () => Navigator.of(context).pop(_controller.text),
        ),
      ],
      children: [
        DsField(
          controller: _controller,
          hint: widget.title,
          autofocus: true,
          margin: EdgeInsets.zero,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ],
    );
  }
}
