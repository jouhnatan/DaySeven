/// The centre of the World view: where the world renderer will land.
///
/// The surface and its place in the shell are settled here while the renderer
/// is still to come, so the rest of the view already has somewhere to belong.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class WorldCanvas extends StatelessWidget {
  const WorldCanvas({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;

    return DsPane(
      key: const Key('world-canvas'),
      editorSurface: true,
      child: Center(
        child: Text(
          'No world yet.',
          style: uiTextStyle(size: 13, color: colors.faint),
        ),
      ),
    );
  }
}
