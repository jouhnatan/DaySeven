/// The chrome shared by the app's few dialogs: a rounded panel on the island
/// tone, and a single-line field that matches the rest of the interface.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/theme.dart';

class DsDialog extends StatelessWidget {
  const DsDialog({
    super.key,
    required this.actions,
    required this.children,
    this.title,
    this.width = 320,
  });

  final List<Widget> actions;
  final List<Widget> children;
  final Widget? title;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return AlertDialog(
      backgroundColor: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.island),
        side: BorderSide(color: colors.border),
      ),
      title: title,
      content: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
      actions: actions,
    );
  }
}

class DsField extends StatelessWidget {
  const DsField({
    super.key,
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.autofocus = false,
    this.onSubmitted,
    this.margin = const EdgeInsets.only(bottom: 8),
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.editorSurface,
        borderRadius: const BorderRadius.all(DsRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        onSubmitted: onSubmitted,
        style: uiTextStyle(size: 13, color: colors.text),
        cursorColor: colors.text,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: uiTextStyle(size: 13, color: colors.muted),
        ),
      ),
    );
  }
}

enum DsDialogActionTone { normal, muted, danger }

/// A dialog action with the app's typography and semantic colour treatment.
class DsDialogAction extends StatelessWidget {
  const DsDialogAction({
    super.key,
    required this.label,
    required this.onPressed,
    this.tone = DsDialogActionTone.normal,
  });

  final String label;
  final VoidCallback? onPressed;
  final DsDialogActionTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final color = switch (tone) {
      DsDialogActionTone.normal => colors.text,
      DsDialogActionTone.muted => colors.muted,
      DsDialogActionTone.danger => Theme.of(context).colorScheme.error,
    };
    return TextButton(
      onPressed: onPressed,
      child: Text(label, style: uiTextStyle(size: 13, color: color)),
    );
  }
}
