/// Formatting controls shown inside the editor-width toolbar island.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/editing_focus.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/alignment_controls.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/bold_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/document_link_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/divider_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/heading_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/image_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/italic_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/document_spacing_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/strikethrough_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/special_character_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/controls/underline_control.dart';
import 'package:dayseven/features/editing_toolbar/ui/special_character_picker.dart';
import 'package:dayseven/shared/ui/theme.dart';

class EditingToolbar extends ConsumerWidget {
  const EditingToolbar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(editingFocusProvider);
    final notifier = ref.read(editingFocusProvider.notifier);

    if (focus == null) return const SizedBox.shrink();

    return Focus(
      // Toolbar interaction must never take the editor's focus or selection.
      canRequestFocus: false,
      descendantsAreFocusable: false,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          HeadingControl(
            level: focus.headingLevel,
            onPick: notifier.setHeadingLevel,
          ),
          const SizedBox(width: DsSpace.controlGap),
          BoldControl(
            active: focus.isActive(EditingFormat.bold),
            onPressed: () => notifier.toggleFormat(EditingFormat.bold),
          ),
          const SizedBox(width: DsSpace.controlGap),
          ItalicControl(
            active: focus.isActive(EditingFormat.italic),
            onPressed: () => notifier.toggleFormat(EditingFormat.italic),
          ),
          const SizedBox(width: DsSpace.controlGap),
          StrikethroughControl(
            active: focus.isActive(EditingFormat.strikethrough),
            onPressed: () => notifier.toggleFormat(EditingFormat.strikethrough),
          ),
          const SizedBox(width: DsSpace.controlGap),
          UnderlineControl(
            active: focus.isActive(EditingFormat.underline),
            onPressed: () => notifier.toggleFormat(EditingFormat.underline),
          ),
          const SizedBox(width: DsSpace.controlGap),
          SpecialCharacterControl(
            onPressed: () async {
              final character = await showSpecialCharacterPicker(context);
              if (character != null) {
                notifier.insertSpecialCharacter(character);
              }
            },
          ),
          const SizedBox(width: DsSpace.controlGap),
          DocumentLinkControl(onPressed: notifier.insertDocumentLink),
          const SizedBox(width: DsSpace.controlGap),
          AlignmentControls(align: focus.align, onPick: notifier.setAlign),
          const SizedBox(width: DsSpace.controlGap),
          DocumentSpacingControl(
            spacing: focus.blockSpacing,
            onPick: notifier.setBlockSpacing,
          ),
          const SizedBox(width: DsSpace.controlGap),
          DividerControl(onPressed: notifier.insertDivider),
          const SizedBox(width: DsSpace.controlGap),
          ImageControl(onPressed: notifier.insertImage),
        ],
      ),
    );
  }
}
