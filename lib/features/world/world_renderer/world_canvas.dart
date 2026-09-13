/// The centre of the World view, rendered as either a flat map or globe.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/world_providers.dart';
import 'package:dayseven/shared/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/world_renderer/engines/dayseven_2d/dayseven_2d_canvas.dart';
import 'package:dayseven/features/world/world_renderer/engines/dayseven_3d/dayseven_3d_canvas.dart';
import 'package:dayseven/shared/ui/controls.dart';

/// Dispatches the selected render mode into the shell's centre slot.
class WorldCanvas extends ConsumerWidget {
  const WorldCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedDimension = ref.watch(selectedWorldDimensionProvider);

    return DsPane(
      key: const Key('world-canvas'),
      editorSurface: true,
      child: selectedDimension == WorldDimension.twoD
          ? const DaySeven2DCanvas()
          : const DaySeven3DCanvas(),
    );
  }
}
