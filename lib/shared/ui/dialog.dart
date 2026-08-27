/// The chrome shared by the app's few dialogs: a rounded panel on the island
/// tone, and a single-line field that matches the rest of the interface.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';
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
      // A dialog is an object on the page, so its edge is the object line
      // rather than the hairline used for divisions inside a surface. The
      // scrim behind it does the separating.
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.all(DsRadius.island),
        side: BorderSide(color: colors.surfaceOutline),
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

class DsField extends StatefulWidget {
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
  State<DsField> createState() => _DsFieldState();
}

class _DsFieldState extends State<DsField> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return Padding(
      padding: widget.margin,
      // The field paints its own box, so the focus state is observed here
      // rather than left to the input decoration, which is switched off.
      child: Focus(
        onFocusChange: (value) => setState(() => _focused = value),
        child: DsFocusRing(
          visible: _focused,
          child: Container(
            height: DsSize.control,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            decoration: BoxDecoration(
              color: colors.island,
              borderRadius: const BorderRadius.all(DsRadius.control),
              border: Border.all(
                color: _focused ? colors.fern : colors.surfaceOutline,
              ),
            ),
            child: TextField(
              controller: widget.controller,
              obscureText: widget.obscure,
              autofocus: widget.autofocus,
              onSubmitted: widget.onSubmitted,
              style: DsType.body(color: colors.text),
              cursorColor: colors.fern,
              cursorWidth: 1.5,
              decoration: InputDecoration(
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: widget.hint,
                // A placeholder is not a label, and it is not a message —
                // which is the one thing the faintest ink may never be.
                hintStyle: DsType.body(color: colors.faint),
              ),
            ),
          ),
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
      DsDialogActionTone.danger => colors.danger,
    };
    return TextButton(
      onPressed: onPressed,
      child: Text(
        label,
        style: DsType.label(
          color: onPressed == null ? colors.faint : color,
          weight: tone == DsDialogActionTone.normal ? 500 : 400,
        ),
      ),
    );
  }
}
