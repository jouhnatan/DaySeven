/// The right-hand Economy pane: Locations, Resources and Simulate.
///
/// Locations edits cities and resource nodes; Resources owns the shared
/// registries every city draws from; Simulate runs the trade routes and shows
/// what has moved. Everything writes through the shared World controller, so
/// the World view reads the same numbers.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/world_providers.dart';
import 'package:dayseven/features/economy/application/economy_providers.dart';
import 'package:dayseven/features/economy/application/economy_simulation.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/color_picker.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/dialog.dart';
import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/slider.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/economy.dart';

class EconomyStatsPane extends ConsumerWidget {
  const EconomyStatsPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openWorldProvider);
    final tab = ref.watch(economyTabProvider);
    final world = open?.world;

    return DsPane(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const DsMenuHeader('Economy'),
          Padding(
            padding: const EdgeInsets.all(DsSpace.row),
            child: SizedBox(
              key: const Key('economy-tabs'),
              height: DsSize.smallControl,
              child: Center(
                child: DsSegmented<EconomyTab>(
                  value: tab,
                  cellHeight: DsSize.smallControl - 6,
                  onPick: (value) =>
                      ref.read(economyTabProvider.notifier).state = value,
                  options: [
                    for (final option in EconomyTab.values)
                      DsSegmentedOption(
                        value: option,
                        semanticLabel: switch (option) {
                          EconomyTab.locations => 'Locations',
                          EconomyTab.resources => 'Resources',
                          EconomyTab.simulate => 'Simulate',
                        },
                        child: Text(switch (option) {
                          EconomyTab.locations => 'Locations',
                          EconomyTab.resources => 'Resources',
                          EconomyTab.simulate => 'Simulate',
                        }, style: uiTextStyle(size: 12, weight: 500)),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const DsSeam.horizontal(),
          Expanded(
            child: world == null
                ? const _NoWorld()
                : switch (tab) {
                    EconomyTab.locations => const _LocationsTab(),
                    EconomyTab.resources => const _ResourcesTab(),
                    EconomyTab.simulate => const _SimulateTab(),
                  },
          ),
        ],
      ),
    );
  }
}

class _NoWorld extends StatelessWidget {
  const _NoWorld();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DsSpace.xl),
        child: Text(
          'Open a Knowledge Base to plan its economy.',
          textAlign: TextAlign.center,
          style: uiTextStyle(size: 13, color: context.ds.muted),
        ),
      ),
    );
  }
}

// --- Locations -------------------------------------------------------------

class _LocationsTab extends ConsumerWidget {
  const _LocationsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedId = ref.watch(selectedEconomyLocationProvider);
    final cities = ref.watch(economyCitiesProvider);
    final world = ref.watch(openWorldProvider)!.world;

    if (selectedId != null) {
      for (final city in cities) {
        if (city.id == selectedId) return _CityDetail(city: city);
      }
      for (final node in world.economy.resourceNodes) {
        if (node.id == selectedId) return _NodeDetail(node: node);
      }
    }
    return const _LocationsList();
  }
}

class _LocationsList extends ConsumerWidget {
  const _LocationsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final cities = ref.watch(economyCitiesProvider);
    final world = ref.watch(openWorldProvider)!.world;
    final economy = world.economy;
    final nodes = economy.resourceNodes;

    if (cities.isEmpty && nodes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DsSpace.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.location_city, size: 46, color: colors.sage),
              const SizedBox(height: DsSpace.m),
              Text(
                'No locations yet',
                style: uiHeaderTextStyle(size: 16, color: colors.text),
              ),
              const SizedBox(height: DsSpace.xs),
              Text(
                'Place a city on the map to start.',
                style: uiTextStyle(size: 12.5, color: colors.muted),
              ),
              const SizedBox(height: DsSpace.m),
              DsLabelButton(
                key: const Key('economy-empty-add-location'),
                label: 'Add location',
                variant: DsButtonVariant.primary,
                onPressed: () => _arm(ref, EconomyTool.addLocation),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(DsSpace.m),
      children: [
        DsLabelButton(
          key: const Key('economy-add-location'),
          label: 'Add location',
          variant: DsButtonVariant.secondary,
          onPressed: () => _arm(ref, EconomyTool.addLocation),
        ),
        if (cities.isNotEmpty) ...[
          const SizedBox(height: DsSpace.m),
          _SectionTitle('Cities'),
          for (final city in cities)
            _LocationRow(
              key: ValueKey('economy-city-row-${city.id}'),
              icon: Icons.location_city,
              color: colors.text,
              name: city.name,
              detail: '${_formatCount(_populationOf(economy, city.id))} people',
              onTap: () {
                ref.read(selectedEconomyLocationProvider.notifier).state =
                    city.id;
              },
            ),
        ],
        if (nodes.isNotEmpty) ...[
          const SizedBox(height: DsSpace.xl),
          _SectionTitle('Resource nodes'),
          for (final node in nodes)
            _LocationRow(
              key: ValueKey('economy-node-row-${node.id}'),
              icon: Icons.diamond_outlined,
              color: TimelineColor.fromId(
                economy.resourceType(node.resourceId)?.color,
              ).color,
              name: _resourceName(economy, node.resourceId),
              detail: node.homeLandmarkId == null
                  ? 'Nobody works it yet'
                  : 'Worked by ${_cityNameOf(ref, node.homeLandmarkId!)}',
              onTap: () {
                ref.read(selectedEconomyLocationProvider.notifier).state =
                    node.id;
              },
            ),
        ],
      ],
    );
  }
}

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    required this.detail,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String name;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsHoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.s,
        vertical: DsSpace.s,
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: DsSpace.s),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: uiTextStyle(size: 13.5, color: colors.text)),
                Text(
                  detail,
                  style: uiTextStyle(size: 11.5, color: colors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CityDetail extends ConsumerWidget {
  const _CityDetail({required this.city});

  final Model3DLandmark city;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final world = ref.watch(openWorldProvider)!.world;
    final economy = world.economy;
    final location =
        economy.locationForLandmark(city.id) ??
        EconomyLocation(id: '', landmarkId: city.id);
    final maxPeople = location.population.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailHeader(
          title: city.name,
          onBack: () =>
              ref.read(selectedEconomyLocationProvider.notifier).state = null,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(DsSpace.m),
            children: [
              _SectionTitle('Population'),
              DsSettingRow(
                key: const Key('economy-population-row'),
                first: true,
                label: 'Population',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _formatCount(location.population),
                      style: uiTextStyle(
                        size: 12,
                        color: colors.muted,
                        tabular: true,
                      ),
                    ),
                    const SizedBox(width: DsSpace.xs),
                    DsSlider(
                      key: const Key('economy-population-slider'),
                      value: location.population.toDouble(),
                      min: 0,
                      max: 100000,
                      divisions: 200,
                      semanticFormatter: (value) =>
                          'Population ${value.round()}',
                      onChanged: (value) => _editLocation(
                        ref,
                        city,
                        (current) => current.copyWith(
                          population: value.round(),
                          personCounts: {
                            for (final entry in current.personCounts.entries)
                              entry.key: entry.value.clamp(0, value.round()),
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: DsSpace.xl),
              _SectionTitle('Resources produced'),
              if (economy.resourceTypes.isEmpty)
                _Hint('Add a resource in the Resources tab first.')
              else
                for (final type in economy.resourceTypes)
                  _CheckRow(
                    key: ValueKey('economy-produced-${type.id}'),
                    label: type.name,
                    color: TimelineColor.fromId(type.color).color,
                    checked: location.resourceIds.contains(type.id),
                    onTap: () => _editLocation(
                      ref,
                      city,
                      (current) => current.copyWith(
                        resourceIds: current.resourceIds.contains(type.id)
                            ? [
                                for (final id in current.resourceIds)
                                  if (id != type.id) id,
                              ]
                            : [...current.resourceIds, type.id],
                      ),
                    ),
                  ),
              const SizedBox(height: DsSpace.xl),
              _SectionTitle(
                'People',
                action: _IconAction(
                  key: const Key('economy-add-person-type'),
                  icon: Icons.add,
                  tooltip: 'Add person type',
                  onPressed: () => unawaited(_addPersonType(context, ref)),
                ),
              ),
              if (economy.personTypes.isEmpty)
                _Hint('No person types yet. Add soldiers, bakers, farmers.')
              else
                for (final type in economy.personTypes)
                  DsSettingRow(
                    key: ValueKey('economy-person-${type.id}'),
                    first: type == economy.personTypes.first,
                    label: type.name,
                    helper: _formatCount(location.personCounts[type.id] ?? 0),
                    trailing: DsSlider(
                      value: (location.personCounts[type.id] ?? 0).toDouble(),
                      min: 0,
                      max: maxPeople <= 0 ? 1 : maxPeople,
                      semanticFormatter: (value) =>
                          '${type.name} ${value.round()}',
                      onChanged: maxPeople <= 0
                          ? null
                          : (value) => _editLocation(
                              ref,
                              city,
                              (current) => current.copyWith(
                                personCounts: {
                                  ...current.personCounts,
                                  type.id: value.round(),
                                },
                              ),
                            ),
                    ),
                  ),
              const SizedBox(height: DsSpace.xl),
              DsLabelButton(
                key: const Key('economy-delete-city'),
                label: 'Delete city',
                variant: DsButtonVariant.danger,
                onPressed: () => unawaited(_deleteCity(context, ref, city)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NodeDetail extends ConsumerWidget {
  const _NodeDetail({required this.node});

  final ResourceNode node;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final world = ref.watch(openWorldProvider)!.world;
    final economy = world.economy;
    final cities = ref.watch(economyCitiesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DetailHeader(
          title: _resourceName(economy, node.resourceId),
          onBack: () =>
              ref.read(selectedEconomyLocationProvider.notifier).state = null,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(DsSpace.m),
            children: [
              DsSettingRow(
                key: const Key('economy-node-resource-row'),
                first: true,
                label: 'Resource',
                trailing: DsLabelButton(
                  label: _resourceName(economy, node.resourceId),
                  onPressed: () => unawaited(_pickResource(context, ref, node)),
                ),
              ),
              DsSettingRow(
                key: const Key('economy-node-home-row'),
                label: 'Worked by',
                trailing: DsLabelButton(
                  label: node.homeLandmarkId == null
                      ? 'Nobody'
                      : _cityName(cities, node.homeLandmarkId!),
                  onPressed: () => unawaited(_pickHome(context, ref, node)),
                ),
              ),
              DsSettingRow(
                label: 'Position',
                trailing: Text(
                  '${node.latitude.toStringAsFixed(1)}, '
                  '${node.longitude.toStringAsFixed(1)}',
                  style: uiTextStyle(
                    size: 12,
                    color: colors.muted,
                    tabular: true,
                  ),
                ),
              ),
              const SizedBox(height: DsSpace.xl),
              DsLabelButton(
                key: const Key('economy-delete-node'),
                label: 'Delete node',
                variant: DsButtonVariant.danger,
                onPressed: () => unawaited(_deleteNode(context, ref, node)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// --- Resources and person types --------------------------------------------

class _ResourcesTab extends ConsumerWidget {
  const _ResourcesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final world = ref.watch(openWorldProvider)!.world;
    final economy = world.economy;

    return ListView(
      padding: const EdgeInsets.all(DsSpace.m),
      children: [
        _SectionTitle(
          'Resources',
          action: _IconAction(
            key: const Key('economy-add-resource'),
            icon: Icons.add,
            tooltip: 'Add resource',
            onPressed: () => unawaited(_addResourceType(context, ref)),
          ),
        ),
        if (economy.resourceTypes.isEmpty)
          _Hint('No resources yet.')
        else
          for (final type in economy.resourceTypes)
            _TypeRow(
              key: ValueKey('economy-resource-row-${type.id}'),
              name: type.name,
              color: TimelineColor.fromId(type.color).color,
              deleteKey: ValueKey('economy-resource-delete-${type.id}'),
              onDelete: () =>
                  unawaited(_deleteResourceType(context, ref, type)),
            ),
        const SizedBox(height: DsSpace.xl),
        _SectionTitle(
          'Person types',
          action: _IconAction(
            key: const Key('economy-add-person-type-section'),
            icon: Icons.add,
            tooltip: 'Add person type',
            onPressed: () => unawaited(_addPersonType(context, ref)),
          ),
        ),
        if (economy.personTypes.isEmpty)
          _Hint('No person types yet. Add soldiers, bakers, farmers.')
        else
          for (final type in economy.personTypes)
            _TypeRow(
              key: ValueKey('economy-person-row-${type.id}'),
              name: type.name,
              color: TimelineColor.fromId(type.color).color,
              deleteKey: ValueKey('economy-person-delete-${type.id}'),
              onDelete: () => unawaited(_deletePersonType(context, ref, type)),
            ),
        const SizedBox(height: DsSpace.m),
        _Hint('Person types are shared by every city that uses them.'),
      ],
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    super.key,
    required this.name,
    required this.color,
    required this.deleteKey,
    required this.onDelete,
  });

  final String name;
  final Color color;
  final Key deleteKey;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      height: DsSize.listRow,
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: DsSpace.s),
          Expanded(
            child: Text(
              name,
              style: uiTextStyle(size: 13.5, color: colors.text),
            ),
          ),
          Tooltip(
            message: 'Delete $name',
            child: DsButton(
              key: deleteKey,
              semanticLabel: 'Delete $name',
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.s),
              onPressed: onDelete,
              child: Icon(Icons.delete_outline, size: 16, color: colors.muted),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Simulate --------------------------------------------------------------

class _SimulateTab extends ConsumerWidget {
  const _SimulateTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.ds;
    final world = ref.watch(openWorldProvider)!.world;
    final economy = world.economy;
    final cities = ref.watch(economyCitiesProvider);
    final simulation = ref.watch(economySimulationProvider);
    final selectedRoute = ref.watch(selectedEconomyRouteProvider);
    final stockpiles = simulation.simulation?.stockpiles ?? const {};

    return ListView(
      padding: const EdgeInsets.all(DsSpace.m),
      children: [
        _SectionTitle(
          'Trade routes',
          action: _IconAction(
            key: const Key('economy-add-route'),
            icon: Icons.add,
            tooltip: 'Add trade route',
            onPressed: () {
              ref.read(economyTabProvider.notifier).state = EconomyTab.simulate;
              _arm(ref, EconomyTool.addRoute);
            },
          ),
        ),
        if (economy.tradeRoutes.isEmpty)
          _Hint('Connect two cities to trade between them.')
        else
          for (final route in economy.tradeRoutes)
            DsHoverRow(
              key: ValueKey('economy-route-row-${route.id}'),
              selected: route.id == selectedRoute,
              onTap: () {
                ref.read(selectedEconomyRouteProvider.notifier).state =
                    route.id;
              },
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_cityName(cities, route.fromLandmarkId)}'
                      ' to '
                      '${_cityName(cities, route.toLandmarkId)}',
                      style: uiTextStyle(size: 13, color: colors.text),
                    ),
                  ),
                  Tooltip(
                    message: 'Delete route',
                    child: DsButton(
                      key: ValueKey('economy-route-delete-${route.id}'),
                      semanticLabel: 'Delete route',
                      height: 28,
                      padding: const EdgeInsets.symmetric(
                        horizontal: DsSpace.s,
                      ),
                      onPressed: () =>
                          unawaited(_deleteRoute(context, ref, route)),
                      child: Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: colors.muted,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        const SizedBox(height: DsSpace.xl),
        Row(
          children: [
            DsLabelButton(
              key: const Key('economy-simulate-play'),
              label: simulation.isRunning ? 'Pause' : 'Play',
              onPressed: simulation.simulation == null
                  ? null
                  : simulation.toggle,
            ),
            const SizedBox(width: DsSpace.s),
            DsLabelButton(
              key: const Key('economy-simulate-reset'),
              label: 'Reset',
              variant: DsButtonVariant.quiet,
              onPressed: simulation.reset,
            ),
            const Spacer(),
            DsSegmented<double>(
              key: const Key('economy-simulate-speed'),
              value: simulation.speed,
              cellHeight: DsSize.smallControl - 6,
              onPick: simulation.setSpeed,
              options: const [
                DsSegmentedOption(
                  value: 0.5,
                  semanticLabel: 'Half speed',
                  child: Text('0.5x'),
                ),
                DsSegmentedOption(
                  value: 1,
                  semanticLabel: 'Normal speed',
                  child: Text('1x'),
                ),
                DsSegmentedOption(
                  value: 2,
                  semanticLabel: 'Double speed',
                  child: Text('2x'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: DsSpace.xl),
        _SectionTitle('Trade so far'),
        if (stockpiles.isEmpty)
          _Hint('Press play and cargo will start moving.')
        else
          for (final entry in stockpiles.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: DsSpace.row),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      _cityName(cities, entry.key),
                      style: uiTextStyle(size: 13.5, color: colors.text),
                    ),
                  ),
                  Text(
                    [
                      for (final resource in entry.value.entries)
                        '${_resourceName(economy, resource.key)} '
                            '${resource.value}',
                    ].join(', '),
                    textAlign: TextAlign.right,
                    style: uiTextStyle(
                      size: 12,
                      color: colors.muted,
                      tabular: true,
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

// --- Shared pieces ---------------------------------------------------------

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Container(
      height: DsSize.listRow,
      padding: const EdgeInsets.symmetric(horizontal: DsSpace.s),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: [
          Tooltip(
            message: 'Back to locations',
            child: DsButton(
              key: const Key('economy-back'),
              semanticLabel: 'Back to locations',
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: DsSpace.xs),
              onPressed: onBack,
              child: Icon(Icons.arrow_back, size: 16, color: colors.text),
            ),
          ),
          const SizedBox(width: DsSpace.xs),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: uiHeaderTextStyle(size: 14.5, color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.xs),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: uiHeaderTextStyle(size: 14.5, color: colors.text),
            ),
          ),
          ?action,
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return Tooltip(
      message: tooltip,
      child: DsButton(
        semanticLabel: tooltip,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: DsSpace.s),
        onPressed: onPressed,
        child: Icon(icon, size: 16, color: colors.text),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: DsSpace.s),
      child: Text(
        message,
        style: uiTextStyle(size: 12.5, color: context.ds.muted),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    super.key,
    required this.label,
    required this.color,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final Color color;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.ds;
    return DsHoverRow(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.s,
        vertical: DsSpace.row,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 18,
            child: checked
                ? Icon(Icons.check, size: 14, color: colors.fern)
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: DsSpace.xs),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: DsSpace.s),
          Expanded(
            child: Text(
              label,
              style: uiTextStyle(size: 13.5, color: colors.text),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Edits -----------------------------------------------------------------

void _arm(WidgetRef ref, EconomyTool tool) {
  ref.read(economyToolProvider.notifier).state = tool;
  ref.read(economyRouteStartProvider.notifier).state = null;
}

void _editLocation(
  WidgetRef ref,
  Model3DLandmark city,
  EconomyLocation Function(EconomyLocation current) update,
) {
  final controller = ref.read(openWorldProvider.notifier);
  final world = ref.read(openWorldProvider)!.world;
  final current =
      world.economy.locationForLandmark(city.id) ??
      EconomyLocation(id: newId(), landmarkId: city.id);
  controller.updateEconomy(world.economy.withLocation(update(current)));
}

Future<void> _addPersonType(BuildContext context, WidgetRef ref) async {
  final result = await _askForType(
    context,
    title: 'New person type',
    hint: 'Soldiers',
  );
  if (result == null) return;
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(
        world.economy.withPersonType(
          PersonType(id: newId(), name: result.name, color: result.color.id),
        ),
      );
}

Future<void> _addResourceType(BuildContext context, WidgetRef ref) async {
  final result = await _askForType(
    context,
    title: 'New resource',
    hint: 'Iron',
  );
  if (result == null) return;
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(
        world.economy.withResourceType(
          ResourceType(id: newId(), name: result.name, color: result.color.id),
        ),
      );
}

Future<({String name, TimelineColor color})?> _askForType(
  BuildContext context, {
  required String title,
  required String hint,
}) => showDialog<({String name, TimelineColor color})>(
  context: context,
  builder: (_) => _TypePromptDialog(title: title, hint: hint),
);

class _TypePromptDialog extends StatefulWidget {
  const _TypePromptDialog({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  State<_TypePromptDialog> createState() => _TypePromptDialogState();
}

class _TypePromptDialogState extends State<_TypePromptDialog> {
  final TextEditingController _controller = TextEditingController();
  TimelineColor _color = TimelineColor.fern;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop((name: name, color: _color));
  }

  @override
  Widget build(BuildContext context) {
    return DsDialog(
      width: 280,
      title: Text(
        widget.title,
        style: uiHeaderTextStyle(size: 16, color: context.ds.text),
      ),
      actions: [
        DsDialogAction(
          label: 'Cancel',
          tone: DsDialogActionTone.muted,
          onPressed: () => Navigator.of(context).pop(),
        ),
        DsDialogAction(label: 'Add', onPressed: _submit),
      ],
      children: [
        DsField(
          controller: _controller,
          hint: widget.hint,
          autofocus: true,
          margin: const EdgeInsets.only(bottom: DsSpace.sm),
          onSubmitted: (_) => _submit(),
        ),
        Row(
          children: [
            Text(
              'Colour',
              style: uiTextStyle(size: 13, color: context.ds.text),
            ),
            const Spacer(),
            DsColorPicker(
              selectedColor: _color,
              tooltipPrefix: 'Colour',
              onColorSelected: (value) => setState(() => _color = value),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _deletePersonType(
  BuildContext context,
  WidgetRef ref,
  PersonType type,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Delete person type',
    body: 'Delete "${type.name}"? Every city that lists them loses them.',
  );
  if (!confirmed) return;
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(world.economy.withoutPersonType(type.id));
}

Future<void> _deleteResourceType(
  BuildContext context,
  WidgetRef ref,
  ResourceType type,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Delete resource',
    body:
        'Delete "${type.name}"? Cities stop producing it, and nodes and '
        'routes that carried it are cleared.',
  );
  if (!confirmed) return;
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(world.economy.withoutResourceType(type.id));
}

Future<void> _deleteCity(
  BuildContext context,
  WidgetRef ref,
  Model3DLandmark city,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Delete city',
    body:
        'Delete "${city.name}"? It is removed from the World map too, along '
        'with its routes and nodes.',
  );
  if (!confirmed) return;
  ref.read(selectedEconomyLocationProvider.notifier).state = null;
  ref.read(openWorldProvider.notifier).removeLandmark(city.id);
}

Future<void> _deleteNode(
  BuildContext context,
  WidgetRef ref,
  ResourceNode node,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Delete resource node',
    body: 'Delete this resource node? Workers assigned to it stop travelling.',
  );
  if (!confirmed) return;
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  ref.read(selectedEconomyLocationProvider.notifier).state = null;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(world.economy.withoutResourceNode(node.id));
}

Future<void> _deleteRoute(
  BuildContext context,
  WidgetRef ref,
  TradeRoute route,
) async {
  final confirmed = await _confirm(
    context,
    title: 'Delete trade route',
    body: 'Delete this trade route? The cities and their people stay.',
  );
  if (!confirmed) return;
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  ref.read(selectedEconomyRouteProvider.notifier).state = null;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(world.economy.withoutTradeRoute(route.id));
}

Future<void> _pickResource(
  BuildContext context,
  WidgetRef ref,
  ResourceNode node,
) async {
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  final menu = DsDropdownMenuList<String>();
  for (final type in world.economy.resourceTypes) {
    menu.pushItem(
      value: type.id,
      label: type.name,
      isChecked: type.id == node.resourceId,
    );
  }
  final choice = await menu.show(context);
  if (choice == null) return;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(
        world.economy.withResourceNode(node.copyWith(resourceId: choice)),
      );
}

Future<void> _pickHome(
  BuildContext context,
  WidgetRef ref,
  ResourceNode node,
) async {
  final world = ref.read(openWorldProvider)?.world;
  if (world == null) return;
  final cities = ref.read(economyCitiesProvider);
  final menu = DsDropdownMenuList<String>();
  menu.pushItem(
    value: '',
    label: 'Nobody',
    isChecked: node.homeLandmarkId == null,
  );
  for (final city in cities) {
    menu.pushItem(
      value: city.id,
      label: city.name,
      isChecked: city.id == node.homeLandmarkId,
    );
  }
  final choice = await menu.show(context);
  if (choice == null) return;
  ref
      .read(openWorldProvider.notifier)
      .updateEconomy(
        world.economy.withResourceNode(
          choice.isEmpty
              ? node.copyWith(clearHomeLandmark: true)
              : node.copyWith(homeLandmarkId: choice),
        ),
      );
}

Future<bool> _confirm(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => DsDialog(
      title: Text(
        title,
        style: uiHeaderTextStyle(size: 16, color: context.ds.text),
      ),
      actions: [
        DsDialogAction(
          label: 'Cancel',
          tone: DsDialogActionTone.muted,
          onPressed: () => Navigator.of(context).pop(false),
        ),
        DsDialogAction(
          label: 'Delete',
          tone: DsDialogActionTone.danger,
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
      children: [
        Text(body, style: uiTextStyle(size: 13, color: context.ds.muted)),
      ],
    ),
  );
  return confirmed ?? false;
}

// --- Text helpers ----------------------------------------------------------

int _populationOf(WorldEconomy economy, String landmarkId) =>
    economy.locationForLandmark(landmarkId)?.population ?? 0;

String _resourceName(WorldEconomy economy, String resourceId) =>
    economy.resourceType(resourceId)?.name ?? 'Resource';

String _cityName(List<Model3DLandmark> cities, String landmarkId) {
  for (final city in cities) {
    if (city.id == landmarkId) return city.name;
  }
  return 'a missing city';
}

String _cityNameOf(WidgetRef ref, String landmarkId) {
  for (final city in ref.read(economyCitiesProvider)) {
    if (city.id == landmarkId) return city.name;
  }
  return 'a missing city';
}

String _formatCount(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
