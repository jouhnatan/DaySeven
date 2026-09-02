/// The left settings pane of the World view.
///
/// Its controls arrive with the World settings slices; for now the pane only
/// establishes the region and its heading.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/controls.dart';

class WorldSettingsPane extends StatelessWidget {
  const WorldSettingsPane({super.key});

  @override
  Widget build(BuildContext context) {
    return DsPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [const DsMenuHeader('World')],
      ),
    );
  }
}
