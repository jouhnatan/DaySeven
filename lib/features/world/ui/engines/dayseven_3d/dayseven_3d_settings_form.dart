/// The settings form owned by the native DaySeven 3D engine.
///
/// Provides visual configuration of planetary geometry, astronomy,
/// environment (atmosphere, ocean, sun lighting), multi-layer texture stack
/// (equirectangular PNG import), and landmarks linked to Knowledge Base documents.
library;

import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/features/world/application/world_controller.dart';
import 'package:dayseven/features/world/application/world_providers.dart';
import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/domain/world_layer.dart';
import 'package:dayseven/features/world/export/world_3d_exporter.dart';
import 'package:dayseven/features/world/ui/engines/dayseven_3d/landmark_dialog.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/theme.dart';

class DaySeven3DSettingsForm extends ConsumerStatefulWidget {
  const DaySeven3DSettingsForm({super.key});

  @override
  ConsumerState<DaySeven3DSettingsForm> createState() =>
      _DaySeven3DSettingsFormState();
}

class _DaySeven3DSettingsFormState
    extends ConsumerState<DaySeven3DSettingsForm> {
  bool _importing = false;
  Model3DLayerType _selectedImportType = Model3DLayerType.heightmap;

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openWorldProvider);
    if (open == null) return const SizedBox.shrink();

    final colors = context.ds;
    final model = open.world.model3d ?? DaySeven3DModel();
    final controller = ref.read(openWorldProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const DsMenuHeader('3D Model & Environment'),
        const SizedBox(height: DsSpace.m),

        // --- Layers Stack ---
        _buildSectionTitle('Texture Layers', colors),
        const SizedBox(height: DsSpace.sm),
        if (model.layers.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s),
            child: Text(
              'No texture layers attached. Import an equirectangular PNG below.',
              style: uiTextStyle(size: 13, color: colors.muted),
            ),
          )
        else
          for (final layer in model.layers) ...[
            _ModelLayerRow(layer: layer),
            const SizedBox(height: DsSpace.xs),
          ],

        const SizedBox(height: DsSpace.sm),
        Row(
          children: [
            Expanded(
              child: DsButton(
                key: const Key('dayseven-3d-import-layer-button'),
                variant: DsButtonVariant.primary,
                onPressed: _importing ? null : _importLayer,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_importing) ...[
                      SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.faint,
                        ),
                      ),
                      const SizedBox(width: DsSpace.row),
                    ],
                    Text(
                      _importing
                          ? 'Importing…'
                          : 'Import ${_selectedImportType.label}',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: DsSpace.sm),
            PopupMenuButton<Model3DLayerType>(
              tooltip: 'Choose layer type to import',
              icon: Icon(Icons.tune, size: 18, color: colors.muted),
              onSelected: (type) => setState(() => _selectedImportType = type),
              itemBuilder: (context) => [
                for (final type in Model3DLayerType.values)
                  PopupMenuItem(
                    value: type,
                    child: Text(type.label, style: uiTextStyle(size: 13)),
                  ),
              ],
            ),
          ],
        ),

        const SizedBox(height: DsSpace.xl),

        // --- Environment Settings ---
        _buildSectionTitle('Environment', colors),
        const SizedBox(height: DsSpace.sm),
        DsSettingRow(
          key: const Key('dayseven-3d-atmosphere-setting'),
          label: 'Atmosphere',
          trailing: Switch.adaptive(
            value: model.environment.atmosphere.enabled,
            activeTrackColor: colors.fern,
            onChanged: (enabled) {
              controller.updateModel3D(
                model.copyWith(
                  environment: model.environment.copyWith(
                    atmosphere: model.environment.atmosphere.copyWith(
                      enabled: enabled,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        DsSettingRow(
          key: const Key('dayseven-3d-ocean-setting'),
          label: 'Ocean / Hydrosphere',
          trailing: Switch.adaptive(
            value: model.environment.ocean.enabled,
            activeTrackColor: colors.fern,
            onChanged: (enabled) {
              controller.updateModel3D(
                model.copyWith(
                  environment: model.environment.copyWith(
                    ocean: model.environment.ocean.copyWith(enabled: enabled),
                  ),
                ),
              );
            },
          ),
        ),
        if (model.environment.ocean.enabled)
          DsSettingRow(
            key: const Key('dayseven-3d-sea-level-setting'),
            label: 'Sea Level',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${(model.environment.ocean.seaLevel * 100).toStringAsFixed(0)}%',
                  style: uiTextStyle(size: 12, color: colors.muted),
                ),
                const SizedBox(width: DsSpace.xs),
                SizedBox(
                  width: 110,
                  child: SliderTheme(
                    data: _sliderTheme(context),
                    child: Slider(
                      value: model.environment.ocean.seaLevel,
                      min: -1.0,
                      max: 1.0,
                      semanticFormatterCallback: (val) =>
                          'Sea level ${(val * 100).toStringAsFixed(0)}%',
                      onChanged: (val) {
                        controller.updateModel3D(
                          model.copyWith(
                            environment: model.environment.copyWith(
                              ocean: model.environment.ocean.copyWith(
                                seaLevel: val,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        DsSettingRow(
          key: const Key('dayseven-3d-sun-azimuth-setting'),
          label: 'Sunlight Direction',
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${model.environment.lighting.sunAzimuthDeg.toStringAsFixed(0)}°',
                style: uiTextStyle(size: 12, color: colors.muted),
              ),
              const SizedBox(width: DsSpace.xs),
              SizedBox(
                width: 110,
                child: SliderTheme(
                  data: _sliderTheme(context),
                  child: Slider(
                    value: model.environment.lighting.sunAzimuthDeg,
                    min: 0.0,
                    max: 360.0,
                    semanticFormatterCallback: (val) =>
                        'Sunlight azimuth ${val.toStringAsFixed(0)} degrees',
                    onChanged: (val) {
                      controller.updateModel3D(
                        model.copyWith(
                          environment: model.environment.copyWith(
                            lighting: model.environment.lighting.copyWith(
                              sunAzimuthDeg: val,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: DsSpace.xl),

        // --- Planetary Geometry ---
        _buildSectionTitle('Planetary Geometry', colors),
        const SizedBox(height: DsSpace.sm),
        DsSettingRow(
          key: const Key('dayseven-3d-radius-setting'),
          label: 'Radius (km)',
          trailing: Text(
            '${model.geometry.radiusKm.toStringAsFixed(0)} km',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),
        DsSettingRow(
          key: const Key('dayseven-3d-axial-tilt-setting'),
          label: 'Axial Tilt',
          trailing: Text(
            '${model.astronomy.axialTiltDeg.toStringAsFixed(1)}°',
            style: uiTextStyle(size: 13, color: colors.text),
          ),
        ),

        const SizedBox(height: DsSpace.xl),

        // --- Landmarks / Points of Interest ---
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildSectionTitle('Landmarks (${model.landmarks.length})', colors),
            IconButton(
              key: const Key('dayseven-3d-add-landmark-button'),
              icon: Icon(
                Icons.add_location_alt_outlined,
                size: 18,
                color: colors.fern,
              ),
              tooltip: 'Add landmark pin',
              onPressed: () => _showAddLandmarkDialog(context, controller),
            ),
          ],
        ),
        const SizedBox(height: DsSpace.sm),
        if (model.landmarks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: DsSpace.s),
            child: Text(
              'No landmarks placed. Click + to place pins on the globe.',
              style: uiTextStyle(size: 13, color: colors.muted),
            ),
          )
        else
          for (final landmark in model.landmarks) ...[
            _LandmarkRow(landmark: landmark),
            const SizedBox(height: DsSpace.xs),
          ],

        const SizedBox(height: DsSpace.xl),

        // --- Export 3D World ---
        _buildSectionTitle('Export 3D World', colors),
        const SizedBox(height: DsSpace.sm),
        Row(
          children: [
            Expanded(
              child: DsButton(
                key: const Key('export-model-json-button'),
                variant: DsButtonVariant.secondary,
                semanticLabel: 'Export model metadata as JSON',
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpace.xs,
                  vertical: DsSpace.s,
                ),
                onPressed: () => _exportFile(
                  title: open.world.title,
                  model: model,
                  extension: 'json',
                  typeGroup: const XTypeGroup(
                    label: 'JSON',
                    extensions: ['json'],
                    uniformTypeIdentifiers: ['public.json'],
                  ),
                  exporter: (model, title) => const World3DExporter()
                      .exportModelJson(model, worldTitle: title),
                ),
                child: const Text('Export JSON', maxLines: 1),
              ),
            ),
            const SizedBox(width: DsSpace.xs),
            Expanded(
              child: DsButton(
                key: const Key('export-geojson-button'),
                variant: DsButtonVariant.secondary,
                semanticLabel: 'Export landmarks and regions as GeoJSON',
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpace.xs,
                  vertical: DsSpace.s,
                ),
                onPressed: () => _exportFile(
                  title: open.world.title,
                  model: model,
                  extension: 'geojson',
                  typeGroup: const XTypeGroup(
                    label: 'GeoJSON',
                    extensions: ['geojson', 'json'],
                    uniformTypeIdentifiers: ['public.json'],
                  ),
                  exporter: (model, title) => const World3DExporter()
                      .exportGeoJson(model, worldTitle: title),
                ),
                child: const Text('Export GeoJSON', maxLines: 1),
              ),
            ),
            const SizedBox(width: DsSpace.xs),
            Expanded(
              child: DsButton(
                key: const Key('export-threejs-html-button'),
                variant: DsButtonVariant.secondary,
                semanticLabel: 'Export standalone WebGL 3D Viewer HTML',
                padding: const EdgeInsets.symmetric(
                  horizontal: DsSpace.xs,
                  vertical: DsSpace.s,
                ),
                onPressed: () => _exportFile(
                  title: open.world.title,
                  model: model,
                  extension: 'html',
                  typeGroup: const XTypeGroup(
                    label: 'HTML',
                    extensions: ['html', 'htm'],
                    uniformTypeIdentifiers: ['public.html'],
                  ),
                  exporter: (model, title) => const World3DExporter()
                      .exportStandaloneThreeJsHtml(model, worldTitle: title),
                ),
                child: const Text('Export 3D HTML', maxLines: 1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _exportFile({
    required String title,
    required DaySeven3DModel model,
    required String extension,
    required XTypeGroup typeGroup,
    required String Function(DaySeven3DModel model, String title) exporter,
  }) async {
    try {
      final base = title.trim().isEmpty ? 'World' : sanitizeNodeName(title);
      final cleanTitle = base.isEmpty ? 'World' : base;
      final location = await getSaveLocation(
        suggestedName: '$cleanTitle.$extension',
        acceptedTypeGroups: [typeGroup],
      );
      if (location == null || !mounted) return;

      final content = exporter(model, cleanTitle);
      await File(location.path).writeAsString(content);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Exported to ${location.path}')));
    } catch (e) {
      _showError('Export failed: $e');
    }
  }

  Widget _buildSectionTitle(String title, DsColors colors) => Text(
    title,
    style: uiTextStyle(size: 11, weight: 600, color: colors.muted),
  );

  SliderThemeData _sliderTheme(BuildContext context) {
    final colors = context.ds;
    return SliderTheme.of(context).copyWith(
      activeTrackColor: colors.fern,
      inactiveTrackColor: colors.border,
      thumbColor: colors.fern,
      trackHeight: 3,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
    );
  }

  Future<void> _importLayer() async {
    if (_importing || ref.read(openWorldProvider) == null) return;

    setState(() => _importing = true);
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'PNG',
            extensions: ['png'],
            uniformTypeIdentifiers: ['public.png'],
          ),
        ],
      );
      if (file == null || !mounted) return;

      final layer = await ref
          .read(worldAssetRepositoryProvider)
          .importLayer(
            id: newId(),
            kind: WorldLayerKind.heightmap,
            source: File(file.path),
          );
      if (!mounted) return;

      final controller = ref.read(openWorldProvider.notifier);
      final modelLayer = Model3DLayer(
        id: layer.id,
        name:
            '${_selectedImportType.label} ${layer.metadata?.width ?? ""}x${layer.metadata?.height ?? ""}'
                .trim(),
        type: _selectedImportType,
        assetId: layer.assetId,
        visible: true,
      );

      controller.addModel3DLayer(modelLayer);
    } on KbException catch (error) {
      _showError(error.message);
    } on Object catch (error) {
      _showError('Could not import texture layer: $error');
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showAddLandmarkDialog(
    BuildContext context,
    WorldController controller,
  ) async {
    await showLandmarkDialog(
      context: context,
      controller: controller,
    );
  }
}

class _ModelLayerRow extends ConsumerWidget {
  const _ModelLayerRow({required this.layer});

  final Model3DLayer layer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final controller = ref.read(openWorldProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.sm,
        vertical: DsSpace.xs,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(DsRadius.island),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              layer.visible ? Icons.visibility : Icons.visibility_off,
              size: 16,
              color: layer.visible ? colors.text : colors.muted,
            ),
            tooltip: layer.visible ? 'Hide layer' : 'Show layer',
            onPressed: () =>
                controller.setModel3DLayerVisible(layer.id, !layer.visible),
          ),
          const SizedBox(width: DsSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiTextStyle(size: 13, weight: 500),
                ),
                Text(
                  layer.type.label,
                  style: uiTextStyle(size: 11, color: colors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: colors.muted),
            tooltip: 'Remove layer',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => DsDialog(
                  title: Text(
                    'Remove “${layer.name}”?',
                    style: uiTextStyle(
                      size: 16,
                      weight: 600,
                      color: colors.text,
                    ),
                  ),
                  actions: [
                    DsDialogAction(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      tone: DsDialogActionTone.muted,
                    ),
                    DsDialogAction(
                      label: 'Remove',
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      tone: DsDialogActionTone.danger,
                    ),
                  ],
                  children: [
                    Text(
                      'This removes the texture layer from the 3D model. The source file remains in your Knowledge Base assets.',
                      style: uiTextStyle(size: 13, color: colors.muted),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                controller.removeModel3DLayer(layer.id);
              }
            },
          ),
        ],
      ),
    );
  }
}

class _LandmarkRow extends ConsumerWidget {
  const _LandmarkRow({required this.landmark});

  final Model3DLandmark landmark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final controller = ref.read(openWorldProvider.notifier);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.sm,
        vertical: DsSpace.xs,
      ),
      decoration: BoxDecoration(
        color: colors.cardSurface,
        borderRadius: const BorderRadius.all(DsRadius.island),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.place, size: 16, color: colors.fern),
          const SizedBox(width: DsSpace.xs),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  landmark.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiTextStyle(size: 13, weight: 500),
                ),
                Text(
                  '${landmark.latitude.toStringAsFixed(1)}°, ${landmark.longitude.toStringAsFixed(1)}°'
                  '${landmark.document != null ? " • ${landmark.document}" : ""}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: uiTextStyle(size: 11, color: colors.muted),
                ),
              ],
            ),
          ),
          IconButton(
            key: Key('edit-landmark-${landmark.id}'),
            icon: Icon(Icons.edit_outlined, size: 16, color: colors.muted),
            tooltip: 'Edit landmark',
            onPressed: () => showLandmarkDialog(
              context: context,
              controller: controller,
              existing: landmark,
            ),
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 16, color: colors.muted),
            tooltip: 'Delete landmark',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => DsDialog(
                  title: Text(
                    'Delete “${landmark.name}”?',
                    style: uiTextStyle(
                      size: 16,
                      weight: 600,
                      color: colors.text,
                    ),
                  ),
                  actions: [
                    DsDialogAction(
                      label: 'Cancel',
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      tone: DsDialogActionTone.muted,
                    ),
                    DsDialogAction(
                      label: 'Delete',
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      tone: DsDialogActionTone.danger,
                    ),
                  ],
                  children: [
                    Text(
                      'This removes the landmark pin from the 3D model.',
                      style: uiTextStyle(size: 13, color: colors.muted),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                controller.removeLandmark(landmark.id);
              }
            },
          ),
        ],
      ),
    );
  }
}
