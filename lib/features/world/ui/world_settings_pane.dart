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
import 'package:dayseven/features/world/domain/world_engine.dart';
import 'package:dayseven/features/world/ui/engines/orogen/orogen_settings_form.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

class WorldSettingsPane extends ConsumerWidget {
  const WorldSettingsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final dimension = ref.watch(selectedWorldDimensionProvider);
    final availableEngines = ref.watch(availableEnginesProvider);
    final activeEngine = ref.watch(activeWorldEngineProvider);

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
                    label: 'Dimension',
                    trailing: DsSegmented<WorldDimension>(
                      value: dimension,
                      options: const [
                        DsSegmentedOption(
                          value: WorldDimension.twoD,
                          child: Text('2D'),
                          semanticLabel: 'Two-dimensional',
                        ),
                        DsSegmentedOption(
                          value: WorldDimension.threeD,
                          child: Text('3D'),
                          semanticLabel: 'Three-dimensional',
                        ),
                      ],
                      onPick: (next) {
                        ref
                                .read(selectedWorldDimensionProvider.notifier)
                                .state =
                            next;
                        ref.read(openWorldProvider.notifier).setDimension(next);
                      },
                    ),
                  ),
                  DsSettingRow(
                    key: const Key('world-engine-setting'),
                    label: 'Engine',
                    trailing: Flexible(
                      child: Builder(
                        builder: (buttonContext) => DsButton(
                          key: const Key('world-engine-dropdown'),
                          onPressed: availableEngines.isEmpty
                              ? null
                              : () async {
                                  final menu =
                                      DsDropdownMenuList<WorldEngine>();
                                  for (final engine in availableEngines) {
                                    menu.pushItem(
                                      value: engine,
                                      label: engine.label,
                                    );
                                  }
                                  final choice = await menu.show(buttonContext);
                                  if (choice != null && buttonContext.mounted) {
                                    ref
                                        .read(openWorldProvider.notifier)
                                        .setEngine(choice.id);
                                  }
                                },
                          highlight: colors.selection,
                          height: DsSize.control,
                          padding: const EdgeInsets.symmetric(
                            horizontal: DsSpace.sm,
                            vertical: 10,
                          ),
                          borderRadius: const BorderRadius.all(DsRadius.island),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  activeEngine?.label ??
                                      (availableEngines.isEmpty
                                          ? 'No engines available'
                                          : 'Choose engine…'),
                                  overflow: TextOverflow.ellipsis,
                                  style: uiTextStyle(
                                    size: 13,
                                    color: availableEngines.isEmpty
                                        ? colors.faint
                                        : colors.text,
                                  ),
                                ),
                              ),
                              const SizedBox(width: DsSpace.row),
                              Icon(
                                Icons.expand_more,
                                size: 16,
                                color: colors.muted,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (dimension == WorldDimension.twoD) ...[
                    const SizedBox(height: DsSpace.m),
                    const DsStatusBlock(
                      key: Key('world-no-2d-engines'),
                      icon: Icons.info_outline,
                      headline: 'No 2D engines available',
                      detail: 'Two-dimensional map projection has no engines in this build.',
                    ),
                  ],
                  if (dimension == WorldDimension.threeD &&
                      activeEngine == WorldEngine.orogen) ...[
                    const SizedBox(height: DsSpace.xl),
                    const OrogenSettingsForm(),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
