/// The left settings pane of the World view.
///
/// Dimension and engine belong here because the centre only renders the
/// choice this pane makes. Engine-specific settings stay below that choice,
/// in the engine's own small form.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/ui/engines/dayseven_3d/dayseven_3d_settings_form.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class WorldSettingsPane extends ConsumerStatefulWidget {
  const WorldSettingsPane({super.key});

  @override
  ConsumerState<WorldSettingsPane> createState() => _WorldSettingsPaneState();
}

class _WorldSettingsPaneState extends ConsumerState<WorldSettingsPane> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(openWorldProvider.notifier).loadExisting();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final dimension = ref.watch(selectedWorldDimensionProvider);

    return DsPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DsMenuHeader('World'),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(DsSpace.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DsSettingRow(
                    key: const Key('world-dimension-setting'),
                    first: true,
                    label: 'Render as',
                    trailing: SizedBox(
                      width: 112,
                      child: DsSegmented<WorldDimension>(
                        key: const Key('world-render-mode-toggle'),
                        value: dimension,
                        options: const [
                          DsSegmentedOption(
                            value: WorldDimension.threeD,
                            semanticLabel: 'Render world in 3D',
                            child: Text('3D'),
                          ),
                          DsSegmentedOption(
                            value: WorldDimension.twoD,
                            semanticLabel: 'Render world in 2D',
                            child: Text('2D'),
                          ),
                        ],
                        onPick: (choice) {
                          ref
                                  .read(selectedWorldDimensionProvider.notifier)
                                  .state =
                              choice;
                          ref
                              .read(openWorldProvider.notifier)
                              .setDimension(choice);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: DsSpace.xl),
                  const DaySeven3DSettingsForm(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
