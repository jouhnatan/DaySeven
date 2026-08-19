/// Asks for a single name — a folder's, when creating one.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/app/theme.dart';

Future<String?> askForName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  final colors = context.ds;

  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.island),
        side: BorderSide(color: colors.border),
      ),
      content: SizedBox(
        width: 280,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: colors.editorSurface,
            borderRadius: const BorderRadius.all(DsRadius.control),
            border: Border.all(color: colors.border),
          ),
          child: TextField(
            controller: controller,
            autofocus: true,
            style: aleo(size: 13, color: colors.text),
            cursorColor: colors.text,
            cursorWidth: 1.5,
            onSubmitted: (value) => Navigator.of(context).pop(value),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: title,
              hintStyle: aleo(size: 13, color: colors.muted),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: aleo(size: 13, color: colors.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text('Create', style: aleo(size: 13, color: colors.text)),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
