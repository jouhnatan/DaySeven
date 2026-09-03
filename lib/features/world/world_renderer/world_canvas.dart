/// The centre of the World view: the engine renderer, or its honest empty
/// state while this build has no renderer for the selected dimension.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/domain/world_engine.dart';
import 'package:dayseven/features/world/world_renderer/engines/dayseven_3d/dayseven_3d_canvas.dart';
import 'package:dayseven/features/world/world_renderer/engines/orogen/orogen_canvas.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

/// Dispatches the selected World engine into the shell's centre slot.
class WorldCanvas extends ConsumerWidget {
  const WorldCanvas({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeEngine = ref.watch(activeWorldEngineProvider);
    final selectedDimension = ref.watch(selectedWorldDimensionProvider);
    final showDaySeven3D =
        selectedDimension == WorldDimension.threeD &&
        activeEngine == WorldEngine.dayseven3D;
    final showOrogen =
        selectedDimension == WorldDimension.threeD &&
        // ignore: deprecated_member_use_from_same_package
        activeEngine == WorldEngine.orogen;

    return DsPane(
      key: const Key('world-canvas'),
      editorSurface: true,
      child: showDaySeven3D
          ? const DaySeven3DCanvas()
          : (showOrogen
                ? const OrogenCanvas()
                : Center(
                    child: Text(
                      selectedDimension == WorldDimension.twoD
                          ? 'No 2D engine available yet.'
                          : 'Choose an engine in settings to render the world.',
                      style: uiTextStyle(size: 13, color: context.ds.faint),
                    ),
                  )),
    );
  }
}
