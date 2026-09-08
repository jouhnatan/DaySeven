/// The left settings pane of the World view.
///
/// Dimension and engine belong here because the centre only renders the
/// choice this pane makes. Engine-specific settings stay below that choice,
/// in the engine's own small form.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/world_dimension.dart';
import 'package:dayseven/features/world/ui/engines/dayseven_3d/dayseven_3d_settings_form.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
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
    final colors = context.ds;
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
                    trailing: Flexible(
                      child: Builder(
                        builder: (buttonContext) => DsButton(
                          key: const Key('world-render-mode-dropdown'),
                          onPressed: () async {
                            final menu = DsDropdownMenuList<WorldDimension>()
                              ..pushItem(
                                value: WorldDimension.threeD,
                                label: '3D',
                              )
                              ..pushItem(
                                value: WorldDimension.twoD,
                                label: '2D',
                              );
                            final choice = await menu.show(buttonContext);
                            if (choice == null || !buttonContext.mounted) {
                              return;
                            }
                            ref
                                    .read(
                                      selectedWorldDimensionProvider.notifier,
                                    )
                                    .state =
                                choice;
                            unawaited(
                              ref
                                  .read(openWorldProvider.notifier)
                                  .setDimension(choice),
                            );
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
                                  dimension == WorldDimension.threeD
                                      ? '3D'
                                      : '2D',
                                  overflow: TextOverflow.ellipsis,
                                  style: uiTextStyle(
                                    size: 13,
                                    color: colors.text,
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
