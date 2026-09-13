/// The Economy map: the World's own uploaded map, with cities, resource
/// nodes, trade routes and the live simulation drawn over it.
///
/// The map is never a second upload. It resolves the same `sourceMapLayerId`
/// the World view renders, so both views always show the same image.
library;

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/world_providers.dart';
import 'package:dayseven/features/economy/application/economy_providers.dart';
import 'package:dayseven/features/economy/application/economy_simulation.dart';
import 'package:dayseven/features/economy/domain/trade_simulation.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/name_prompt.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/shared/world/domain/economy.dart';
import 'package:dayseven/shared/world/domain/equirectangular_projection.dart';
import 'package:dayseven/shared/world/domain/world.dart';
import 'package:dayseven/shared/world/domain/world_layer.dart';

class EconomyMapCanvas extends ConsumerStatefulWidget {
  const EconomyMapCanvas({super.key});

  @override
  ConsumerState<EconomyMapCanvas> createState() => _EconomyMapCanvasState();
}

class _EconomyMapCanvasState extends ConsumerState<EconomyMapCanvas> {
  final TransformationController _transform = TransformationController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(openWorldProvider.notifier).loadExisting();
      ref
          .read(economySimulationProvider)
          .configure(ref.read(openWorldProvider)?.world);
    });
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final open = ref.watch(openWorldProvider);
    final session = ref.watch(kbSessionProvider);
    final world = open?.world;
    final simulation = ref.watch(economySimulationProvider);
    ref.listen(openWorldProvider, (_, next) {
      simulation.configure(next?.world);
    });

    final model = world?.model;
    final layer = _sourceLayer(model);
    final assetPath = layer == null || session == null
        ? null
        : session.kb.assetPathFor(layer.assetId);

    if (assetPath == null) {
      return DsPane(
        key: const Key('economy-map-canvas'),
        editorSurface: true,
        child: Center(
          child: DsStatusBlock(
            icon: Icons.map_outlined,
            headline: 'Add a source map',
            detail: session == null
                ? 'Open a Knowledge Base to place cities on a map.'
                : 'Import the same 2:1 PNG or JPEG the World view uses.',
            trailing: session == null
                ? null
                : DsLabelButton(
                    key: const Key('economy-add-map-button'),
                    label: 'Import map',
                    onPressed: () => unawaited(_importMap()),
                  ),
          ),
        ),
      );
    }

    return DsPane(
      key: const Key('economy-map-canvas'),
      editorSurface: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = Size(constraints.maxWidth, constraints.maxHeight);
          final mapSize = _fitTwoToOne(available);
          final origin = Offset(
            (available.width - mapSize.width) / 2,
            (available.height - mapSize.height) / 2,
          );
          final cities = ref.watch(economyCitiesProvider);
          final nodes = world?.economy.resourceNodes ?? const <ResourceNode>[];
          final routes = world?.economy.tradeRoutes ?? const <TradeRoute>[];
          final selectedLocation = ref.watch(selectedEconomyLocationProvider);
          final selectedRoute = ref.watch(selectedEconomyRouteProvider);
          final tool = ref.watch(economyToolProvider);
          final routeStart = ref.watch(economyRouteStartProvider);

          final geometries = [
            for (final route in routes) ?_geometryFor(route, cities, mapSize),
          ];
          final selectedGeometry = selectedRoute == null
              ? null
              : geometries
                    .where((geometry) => geometry.route.id == selectedRoute)
                    .firstOrNull;

          return Stack(
            children: [
              Center(
                child: SizedBox(
                  width: mapSize.width,
                  height: mapSize.height,
                  child: InteractiveViewer(
                    key: const Key('economy-map-viewport'),
                    transformationController: _transform,
                    minScale: 0.5,
                    maxScale: 8,
                    boundaryMargin: const EdgeInsets.all(200),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) => unawaited(
                        _onMapTap(
                          details.localPosition,
                          mapSize,
                          cities,
                          nodes,
                          geometries,
                        ),
                      ),
                      child: SizedBox(
                        key: const Key('economy-map'),
                        width: mapSize.width,
                        height: mapSize.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: Image.file(
                                File(assetPath),
                                fit: BoxFit.fill,
                                gaplessPlayback: true,
                                filterQuality: FilterQuality.medium,
                                errorBuilder: (context, error, stack) =>
                                    const SizedBox.shrink(),
                              ),
                            ),
                            Positioned.fill(
                              child: ListenableBuilder(
                                listenable: simulation,
                                builder: (context, _) => CustomPaint(
                                  key: const Key('economy-route-layer'),
                                  painter: _EconomyMapPainter(
                                    size: mapSize,
                                    geometries: geometries,
                                    simulation: simulation.simulation,
                                    selectedRouteId: selectedRoute,
                                    lineColor: context.ds.muted,
                                    selectedColor: context.ds.fern,
                                    frameColor: context.ds.island,
                                    resourceColor: (id) =>
                                        _resourceColor(context, world, id),
                                  ),
                                ),
                              ),
                            ),
                            for (final city in cities)
                              _cityMarker(
                                city,
                                mapSize,
                                selected: selectedLocation == city.id,
                                routeStart: routeStart == city.id,
                              ),
                            for (final node in nodes)
                              _nodeMarker(
                                node,
                                mapSize,
                                world,
                                selected: selectedLocation == node.id,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Route handles sit above the viewer rather than inside it, so
              // the map's own pan gesture is not competing for the drag.
              Positioned.fill(
                child: ListenableBuilder(
                  listenable: _transform,
                  builder: (context, _) => Stack(
                    clipBehavior: Clip.none,
                    children: [
                      if (selectedGeometry != null)
                        for (
                          var i = 0;
                          i < selectedGeometry.controls.length;
                          i++
                        )
                          _controlHandle(selectedGeometry, i, mapSize, origin),
                    ],
                  ),
                ),
              ),
              if (tool != EconomyTool.none)
                Positioned(
                  top: DsSpace.m,
                  left: 0,
                  right: 0,
                  child: Center(child: _placementHint(tool)),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _cityMarker(
    Model3DLandmark city,
    Size size, {
    required bool selected,
    required bool routeStart,
  }) {
    final position = EquirectangularProjection.geographicToPixels(
      latitude: city.latitude,
      longitude: city.longitude,
      size: size,
    );
    final colors = context.ds;
    return Positioned(
      key: ValueKey('economy-city-${city.id}'),
      left: position.dx - 12,
      top: position.dy - 12,
      child: Tooltip(
        message: city.name,
        child: GestureDetector(
          onTap: () => _onCityTap(city),
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: routeStart ? colors.fern : colors.island,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected || routeStart ? colors.fern : colors.text,
                width: 1.6,
              ),
            ),
            child: Icon(
              Icons.location_city,
              size: 14,
              color: routeStart ? colors.onFern : colors.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _nodeMarker(
    ResourceNode node,
    Size size,
    World? world, {
    required bool selected,
  }) {
    final position = EquirectangularProjection.geographicToPixels(
      latitude: node.latitude,
      longitude: node.longitude,
      size: size,
    );
    final colors = context.ds;
    final color = _resourceColor(context, world, node.resourceId);
    return Positioned(
      key: ValueKey('economy-node-${node.id}'),
      left: position.dx - 9,
      top: position.dy - 9,
      child: Tooltip(
        message: _resourceName(world, node.resourceId),
        child: GestureDetector(
          onTap: () {
            ref.read(selectedEconomyLocationProvider.notifier).state = node.id;
            ref.read(economyTabProvider.notifier).state = EconomyTab.locations;
          },
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              color: colors.island,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? colors.fern : color,
                width: 2,
              ),
            ),
            child: Center(
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controlHandle(
    _RouteGeometry geometry,
    int index,
    Size size,
    Offset origin,
  ) {
    final point = geometry.controls[index];
    final transformed = MatrixUtils.transformPoint(_transform.value, point);
    final position = origin + transformed;
    final colors = context.ds;
    return Positioned(
      key: ValueKey('economy-route-handle-${geometry.route.id}-$index'),
      left: position.dx - 8,
      top: position.dy - 8,
      child: GestureDetector(
        onPanUpdate: (details) {
          final scale = _transform.value.getMaxScaleOnAxis();
          _moveControl(
            geometry.route,
            index,
            Offset(details.delta.dx / scale, details.delta.dy / scale),
            size,
          );
        },
        child: Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: colors.island,
            shape: BoxShape.circle,
            border: Border.all(color: colors.fern, width: 1.6),
          ),
        ),
      ),
    );
  }

  Widget _placementHint(EconomyTool tool) {
    final colors = context.ds;
    final message = switch (tool) {
      EconomyTool.addLocation => 'Click the map to place a city.',
      EconomyTool.addNode => 'Click the map to place a resource node.',
      EconomyTool.addRoute => 'Click one city, then another, to connect them.',
      EconomyTool.none => '',
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DsSpace.sm,
        vertical: DsSpace.s,
      ),
      decoration: BoxDecoration(
        color: colors.island,
        borderRadius: const BorderRadius.all(DsRadius.menu),
        border: Border.all(color: colors.surfaceOutline),
        boxShadow: cfMenuShadow,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(message, style: uiTextStyle(size: 12.5, color: colors.text)),
          const SizedBox(width: DsSpace.sm),
          DsLabelButton(
            key: const Key('economy-tool-cancel'),
            label: 'Cancel',
            variant: DsButtonVariant.quiet,
            height: 28,
            onPressed: _cancelTool,
          ),
        ],
      ),
    );
  }

  void _cancelTool() {
    ref.read(economyToolProvider.notifier).state = EconomyTool.none;
    ref.read(economyRouteStartProvider.notifier).state = null;
  }

  Future<void> _onMapTap(
    Offset local,
    Size size,
    List<Model3DLandmark> cities,
    List<ResourceNode> nodes,
    List<_RouteGeometry> geometries,
  ) async {
    final tool = ref.read(economyToolProvider);
    switch (tool) {
      case EconomyTool.addLocation:
        await _addCityAt(local, size);
      case EconomyTool.addNode:
        _addNodeAt(local, size);
      case EconomyTool.addRoute:
        _continueRoute(local, size, cities);
      case EconomyTool.none:
        final route = _hitRoute(local, geometries);
        ref.read(selectedEconomyRouteProvider.notifier).state = route?.id;
        if (route == null) {
          // Leave the location selection to the markers themselves; a tap on
          // empty map clears it only when nothing was hit.
          final city = _hitCity(local, size, cities);
          final node = _hitNode(local, size, nodes);
          if (city == null && node == null) {
            ref.read(selectedEconomyLocationProvider.notifier).state = null;
          }
        } else {
          ref.read(economyTabProvider.notifier).state = EconomyTab.simulate;
        }
    }
  }

  Future<void> _addCityAt(Offset local, Size size) async {
    final controller = ref.read(openWorldProvider.notifier);
    _cancelTool();
    final name = await askForName(
      context,
      title: 'Name the city',
      actionLabel: 'Add',
    );
    if (!mounted || name == null || name.trim().isEmpty) return;

    final geographic = EquirectangularProjection.pixelsToGeographic(
      position: local,
      size: size,
    );
    final landmark = Model3DLandmark(
      id: newId(),
      name: name.trim(),
      latitude: geographic.latitude,
      longitude: geographic.longitude,
      category: 'city',
    );
    final world = ref.read(openWorldProvider)?.world;
    if (world == null) return;
    controller.addLandmark(landmark);
    controller.updateEconomy(
      world.economy.withLocation(
        EconomyLocation(id: newId(), landmarkId: landmark.id),
      ),
    );
    ref.read(selectedEconomyLocationProvider.notifier).state = landmark.id;
    ref.read(economyTabProvider.notifier).state = EconomyTab.locations;
  }

  void _addNodeAt(Offset local, Size size) {
    final world = ref.read(openWorldProvider)?.world;
    final resourceId =
        ref.read(economyNodeResourceProvider) ??
        (world?.economy.resourceTypes.isNotEmpty ?? false
            ? world!.economy.resourceTypes.first.id
            : null);
    if (world == null || resourceId == null) {
      _cancelTool();
      return;
    }
    final geographic = EquirectangularProjection.pixelsToGeographic(
      position: local,
      size: size,
    );
    final node = ResourceNode(
      id: newId(),
      resourceId: resourceId,
      latitude: geographic.latitude,
      longitude: geographic.longitude,
    );
    ref
        .read(openWorldProvider.notifier)
        .updateEconomy(world.economy.withResourceNode(node));
    ref.read(selectedEconomyLocationProvider.notifier).state = node.id;
    ref.read(economyTabProvider.notifier).state = EconomyTab.locations;
    _cancelTool();
  }

  void _onCityTap(Model3DLandmark city) {
    if (ref.read(economyToolProvider) == EconomyTool.addRoute) {
      _connectRoute(city);
      return;
    }
    ref.read(selectedEconomyLocationProvider.notifier).state = city.id;
    ref.read(economyTabProvider.notifier).state = EconomyTab.locations;
  }

  void _continueRoute(Offset local, Size size, List<Model3DLandmark> cities) {
    final hit = _hitCity(local, size, cities);
    if (hit == null) return;
    _connectRoute(cities.firstWhere((candidate) => candidate.id == hit));
  }

  void _connectRoute(Model3DLandmark hit) {
    final start = ref.read(economyRouteStartProvider);
    if (start == null) {
      ref.read(economyRouteStartProvider.notifier).state = hit.id;
      return;
    }
    if (start == hit.id) {
      ref.read(economyRouteStartProvider.notifier).state = null;
      return;
    }
    final world = ref.read(openWorldProvider)?.world;
    if (world == null) return;
    final cities = ref.read(economyCitiesProvider);
    final from = cities.firstWhere((city) => city.id == start);
    final route = TradeRoute(
      id: newId(),
      fromLandmarkId: start,
      toLandmarkId: hit.id,
      controlPoints: _defaultControls(
        EquirectangularProjection.geographicToUv(
          latitude: from.latitude,
          longitude: from.longitude,
        ),
        EquirectangularProjection.geographicToUv(
          latitude: hit.latitude,
          longitude: hit.longitude,
        ),
      ),
    );
    ref
        .read(openWorldProvider.notifier)
        .updateEconomy(world.economy.withTradeRoute(route));
    ref.read(selectedEconomyRouteProvider.notifier).state = route.id;
    ref.read(economyTabProvider.notifier).state = EconomyTab.simulate;
    _cancelTool();
  }

  void _moveControl(
    TradeRoute route,
    int index,
    Offset deltaPixels,
    Size size,
  ) {
    if (index >= route.controlPoints.length) return;
    final world = ref.read(openWorldProvider)?.world;
    if (world == null) return;
    final points = [
      for (final point in route.controlPoints) [point[0], point[1]],
    ];
    points[index] = [
      (points[index][0] + deltaPixels.dx / size.width).clamp(0.0, 1.0),
      (points[index][1] + deltaPixels.dy / size.height).clamp(0.0, 1.0),
    ];
    ref
        .read(openWorldProvider.notifier)
        .updateEconomy(
          world.economy.withTradeRoute(route.copyWith(controlPoints: points)),
        );
  }

  Future<void> _importMap() async {
    final session = ref.read(kbSessionProvider);
    if (session == null) return;
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: 'PNG or JPEG',
          extensions: ['png', 'jpg', 'jpeg'],
          uniformTypeIdentifiers: ['public.png', 'public.jpeg'],
        ),
      ],
    );
    if (file == null || !mounted) return;
    try {
      final layer = await ref
          .read(worldAssetRepositoryProvider)
          .importLayer(
            id: newId(),
            kind: WorldLayerKind.satellite,
            source: File(file.path),
          );
      if (!mounted) return;
      ref
          .read(openWorldProvider.notifier)
          .setSourceMapLayer(
            Model3DLayer(
              id: layer.id,
              name: file.name,
              type: Model3DLayerType.albedo,
              assetId: layer.assetId,
              visible: true,
            ),
          );
    } on KbException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
    }
  }
}

/// One route, resolved to map pixels for painting and hit testing.
class _RouteGeometry {
  const _RouteGeometry({
    required this.route,
    required this.from,
    required this.to,
    required this.controls,
  });

  final TradeRoute route;
  final Offset from;
  final Offset to;
  final List<Offset> controls;
}

_RouteGeometry? _geometryFor(
  TradeRoute route,
  List<Model3DLandmark> cities,
  Size size,
) {
  final from = _cityById(cities, route.fromLandmarkId);
  final to = _cityById(cities, route.toLandmarkId);
  if (from == null || to == null) return null;
  return _RouteGeometry(
    route: route,
    from: EquirectangularProjection.geographicToPixels(
      latitude: from.latitude,
      longitude: from.longitude,
      size: size,
    ),
    to: EquirectangularProjection.geographicToPixels(
      latitude: to.latitude,
      longitude: to.longitude,
      size: size,
    ),
    controls: [
      for (final point in route.controlPoints)
        if (point.length >= 2)
          Offset(point[0] * size.width, point[1] * size.height),
    ],
  );
}

Model3DLandmark? _cityById(List<Model3DLandmark> cities, String id) {
  for (final city in cities) {
    if (city.id == id) return city;
  }
  return null;
}

String? _hitCity(Offset local, Size size, List<Model3DLandmark> cities) {
  for (final city in cities.reversed) {
    final position = EquirectangularProjection.geographicToPixels(
      latitude: city.latitude,
      longitude: city.longitude,
      size: size,
    );
    if ((position - local).distance <= 16) return city.id;
  }
  return null;
}

String? _hitNode(Offset local, Size size, List<ResourceNode> nodes) {
  for (final node in nodes.reversed) {
    final position = EquirectangularProjection.geographicToPixels(
      latitude: node.latitude,
      longitude: node.longitude,
      size: size,
    );
    if ((position - local).distance <= 14) return node.id;
  }
  return null;
}

TradeRoute? _hitRoute(Offset local, List<_RouteGeometry> geometries) {
  for (final geometry in geometries.reversed) {
    const samples = 48;
    var previous = geometry.from;
    for (var i = 1; i <= samples; i++) {
      final point = _pointOn(geometry, i / samples);
      if (_distanceToSegment(local, previous, point) <= 8) {
        return geometry.route;
      }
      previous = point;
    }
  }
  return null;
}

Offset _pointOn(_RouteGeometry geometry, double t) {
  if (geometry.controls.length < 2) {
    return Offset.lerp(geometry.from, geometry.to, t)!;
  }
  final mt = 1 - t;
  return geometry.from * (mt * mt * mt) +
      geometry.controls[0] * (3 * mt * mt * t) +
      geometry.controls[1] * (3 * mt * t * t) +
      geometry.to * (t * t * t);
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (point - a).distance;
  final t = (((point - a).dx * ab.dx + (point - a).dy * ab.dy) / lengthSquared)
      .clamp(0.0, 1.0);
  return (point - (a + ab * t)).distance;
}

List<List<double>> _defaultControls(Offset from, Offset to) {
  final dx = to.dx - from.dx;
  final dy = to.dy - from.dy;
  final length = math.sqrt(dx * dx + dy * dy);
  if (length == 0) return const [];
  final perpendicular = Offset(-dy / length, dx / length);
  final bend = length * 0.18;
  return [
    [
      (from.dx + dx / 3 + perpendicular.dx * bend).clamp(0.0, 1.0),
      (from.dy + dy / 3 + perpendicular.dy * bend).clamp(0.0, 1.0),
    ],
    [
      (from.dx + dx * 2 / 3 + perpendicular.dx * bend).clamp(0.0, 1.0),
      (from.dy + dy * 2 / 3 + perpendicular.dy * bend).clamp(0.0, 1.0),
    ],
  ];
}

Model3DLayer? _sourceLayer(DaySeven3DModel? model) {
  if (model == null) return null;
  final sourceId = model.sourceMapLayerId;
  if (sourceId != null) {
    for (final layer in model.layers) {
      if (layer.id == sourceId && layer.visible) return layer;
    }
  }
  for (final layer in model.layers) {
    if (layer.visible) return layer;
  }
  return null;
}

Color _resourceColor(BuildContext context, World? world, String resourceId) {
  final type = world?.economy.resourceType(resourceId);
  return TimelineColor.fromId(type?.color).color;
}

String _resourceName(World? world, String resourceId) =>
    world?.economy.resourceType(resourceId)?.name ?? 'Resource';

Size _fitTwoToOne(Size available) {
  if (available.width / available.height > 2) {
    return Size(available.height * 2, available.height);
  }
  return Size(available.width, available.width / 2);
}

class _EconomyMapPainter extends CustomPainter {
  const _EconomyMapPainter({
    required this.size,
    required this.geometries,
    required this.simulation,
    required this.selectedRouteId,
    required this.lineColor,
    required this.selectedColor,
    required this.frameColor,
    required this.resourceColor,
  });

  final Size size;
  final List<_RouteGeometry> geometries;
  final TradeSimulation? simulation;
  final String? selectedRouteId;
  final Color lineColor;
  final Color selectedColor;
  final Color frameColor;
  final Color Function(String resourceId) resourceColor;

  @override
  void paint(Canvas canvas, Size ignored) {
    for (final geometry in geometries) {
      final selected = geometry.route.id == selectedRouteId;
      final path = Path()..moveTo(geometry.from.dx, geometry.from.dy);
      if (geometry.controls.length >= 2) {
        path.cubicTo(
          geometry.controls[0].dx,
          geometry.controls[0].dy,
          geometry.controls[1].dx,
          geometry.controls[1].dy,
          geometry.to.dx,
          geometry.to.dy,
        );
      } else {
        path.lineTo(geometry.to.dx, geometry.to.dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = selected ? 2.4 : 1.6
          ..strokeCap = StrokeCap.round
          ..color = selected ? selectedColor : lineColor,
      );
      _drawArrowHead(canvas, geometry, selected ? selectedColor : lineColor);
    }

    final running = simulation;
    if (running == null) return;
    for (final agent in running.agents) {
      final position = Offset(
        agent.position.dx * size.width,
        agent.position.dy * size.height,
      );
      canvas.drawCircle(position, 4, Paint()..color = frameColor);
      canvas.drawCircle(
        position,
        3,
        Paint()..color = resourceColor(agent.resourceId),
      );
    }
  }

  void _drawArrowHead(Canvas canvas, _RouteGeometry geometry, Color color) {
    final end = _pointOn(geometry, 1);
    final before = _pointOn(geometry, 0.94);
    final direction = end - before;
    if (direction.distance == 0) return;
    final normal = Offset(-direction.dy, direction.dx) / direction.distance;
    final paint = Paint()..color = color;
    canvas.drawPath(
      Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(
          end.dx - direction.dx / direction.distance * 9 + normal.dx * 5,
          end.dy - direction.dy / direction.distance * 9 + normal.dy * 5,
        )
        ..lineTo(
          end.dx - direction.dx / direction.distance * 9 - normal.dx * 5,
          end.dy - direction.dy / direction.distance * 9 - normal.dy * 5,
        )
        ..close(),
      paint,
    );
  }

  @override
  bool shouldRepaint(_EconomyMapPainter oldDelegate) => true;
}
