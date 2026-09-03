/// The small settings form owned by the World Orogen engine.
///
/// It keeps the layer references and the two settings Orogen currently knows
/// about together. More engine-specific controls belong here when the domain
/// model learns about them, rather than being smuggled into the raw World.
library;

import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/orogen_settings.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';

class OrogenSettingsForm extends ConsumerWidget {
  const OrogenSettingsForm({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final open = ref.watch(openWorldProvider);
    if (open == null) return const SizedBox.shrink();

    final rawSettings = open.world.engineSettings['orogen'];
    final settings = OrogenSettings.fromJson(
      rawSettings ?? const <String, Object?>{},
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Layers',
          style: uiTextStyle(size: 13, weight: 600, color: colors.text),
        ),
        const SizedBox(height: DsSpace.s),
        DsButton(
          key: const Key('world-import-layer'),
          height: DsSize.control,
          onPressed: () => _importLayer(context, ref),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: colors.text),
              const SizedBox(width: DsSpace.row),
              Text(
                'Import PNG layer',
                style: uiTextStyle(size: 13, color: colors.text),
              ),
            ],
          ),
        ),
        if (open.world.layers.isNotEmpty) ...[
          const SizedBox(height: DsSpace.s),
          for (final layer in open.world.layers) _LayerRow(layer: layer),
        ],
        const SizedBox(height: DsSpace.xl),
        Text(
          'Orogen settings',
          style: uiTextStyle(size: 13, weight: 600, color: colors.text),
        ),
        DsSettingRow(
          key: const Key('orogen-planet-code-setting'),
          first: true,
          label: 'Planet code',
          trailing: Text(
            settings.planetCode ?? 'None',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        DsSettingRow(
          key: const Key('orogen-active-layer-setting'),
          label: 'Active layer',
          trailing: Text(
            settings.activeLayerId ?? 'None',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
      ],
    );
  }

  Future<void> _importLayer(BuildContext context, WidgetRef ref) async {
    if (ref.read(openWorldProvider) == null) return;

    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'PNG', extensions: ['png']),
      ],
    );
    if (file == null || !context.mounted) return;

    final layer = await ref
        .read(worldAssetRepositoryProvider)
        .importLayer(
          id: newId(),
          kind: WorldLayerKind.heightmap,
          source: File(file.path),
        );
    if (!context.mounted) return;

    final controller = ref.read(openWorldProvider.notifier);
    controller.addLayer(layer);

    final planetCode = layer.metadata?.planetCode;
    if (planetCode != null && planetCode.isNotEmpty) {
      final updated = OrogenSettings(
        planetCode: planetCode,
        activeLayerId: layer.id,
      );
      controller.updateEngineSettings('orogen', updated.toJson());
    }
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({required this.layer});

  final WorldLayer layer;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    final metadata = layer.metadata;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.xs),
      child: Row(
        children: [
          SizedBox.square(
            dimension: DsSize.smallControl,
            child: DsButton(
              key: Key('world-layer-visibility-${layer.id}'),
              height: DsSize.smallControl,
              padding: EdgeInsets.zero,
              semanticLabel: layer.visible
                  ? 'Hide ${layer.kind.label}'
                  : 'Show ${layer.kind.label}',
              onPressed: () => _toggleVisibility(context, layer),
              child: Icon(
                layer.visible
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 16,
                color: colors.text,
              ),
            ),
          ),
          const SizedBox(width: DsSpace.row),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  layer.kind.label,
                  style: uiTextStyle(size: 13, color: colors.text),
                ),
                if (metadata != null)
                  Text(
                    '${metadata.width} × ${metadata.height}',
                    style: uiTextStyle(size: 12, color: colors.muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: DsSpace.row),
          SizedBox.square(
            dimension: DsSize.smallControl,
            child: DsButton(
              key: Key('world-layer-remove-${layer.id}'),
              height: DsSize.smallControl,
              padding: EdgeInsets.zero,
              semanticLabel: 'Remove ${layer.kind.label}',
              variant: DsButtonVariant.danger,
              onPressed: () => _removeLayer(context, layer),
              child: Icon(Icons.delete_outline, size: 16, color: colors.danger),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleVisibility(BuildContext context, WorldLayer layer) {
    final scope = ProviderScope.containerOf(context, listen: false);
    scope
        .read(openWorldProvider.notifier)
        .setLayerVisible(layer.id, !layer.visible);
  }

  void _removeLayer(BuildContext context, WorldLayer layer) {
    final scope = ProviderScope.containerOf(context, listen: false);
    scope.read(openWorldProvider.notifier).removeLayer(layer.id);
  }
}
