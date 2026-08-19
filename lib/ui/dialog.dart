/// The chrome shared by the app's few dialogs: a rounded panel on the island
/// tone, and a single-line field that matches the rest of the interface.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/app/theme.dart';

class DsDialog extends StatelessWidget {
  const DsDialog({super.key, required this.actions, required this.children});

  final List<Widget> actions;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return AlertDialog(
      backgroundColor: colors.island,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.island),
        side: BorderSide(color: colors.border),
      ),
      content: SizedBox(
        width: 320,
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
  });

  final TextEditingController controller;
  final String hint;
  final bool obscure;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.editorSurface,
        borderRadius: const BorderRadius.all(DsRadius.control),
        border: Border.all(color: colors.border),
      ),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: aleo(size: 13, color: colors.text),
        cursorColor: colors.text,
        cursorWidth: 1.5,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          hintText: hint,
          hintStyle: aleo(size: 13, color: colors.muted),
        ),
      ),
    );
  }
}
