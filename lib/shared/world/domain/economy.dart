/// The economy attached to a World: who lives where, what the land offers,
/// and the trade routes between cities.
///
/// It lives inside the World object — not in an object of its own — so the
/// World view and the Economy view read and write the same classes and can
/// never drift apart. Every entry is JSON round-trippable by hand, like the
/// rest of the `.unearth` format.
library;

import 'package:flutter/foundation.dart';

/// One kind of person a city can hold, such as Soldiers or Bakers.
///
/// Types are defined once on the World and referenced by id, so renaming one
/// is a single edit and every city follows.
@immutable
class PersonType {
  const PersonType({required this.id, required this.name, this.color = 'fern'});

  final String id;
  final String name;

  /// Accent colour key from the shared palette.
  final String color;

  PersonType copyWith({String? id, String? name, String? color}) => PersonType(
    id: id ?? this.id,
    name: name ?? this.name,
    color: color ?? this.color,
  );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color};

  static PersonType? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final name = _string(json['name']);
    if (id.isEmpty || name.isEmpty) return null;
    return PersonType(
      id: id,
      name: name,
      color: _string(json['color'], fallback: 'fern'),
    );
  }
}

/// One resource the world can produce, such as Stone, Timber or Gold.
@immutable
class ResourceType {
  const ResourceType({
    required this.id,
    required this.name,
    this.color = 'slate',
  });

  final String id;
  final String name;

  /// Accent colour key from the shared palette.
  final String color;

  ResourceType copyWith({String? id, String? name, String? color}) =>
      ResourceType(
        id: id ?? this.id,
        name: name ?? this.name,
        color: color ?? this.color,
      );

  Map<String, Object?> toJson() => {'id': id, 'name': name, 'color': color};

  static ResourceType? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final name = _string(json['name']);
    if (id.isEmpty || name.isEmpty) return null;
    return ResourceType(
      id: id,
      name: name,
      color: _string(json['color'], fallback: 'slate'),
    );
  }
}

/// The economic profile of one city. The city itself is a World landmark;
/// this is the half of it the Economy view edits, keyed by [landmarkId].
@immutable
class EconomyLocation {
  EconomyLocation({
    required this.id,
    required this.landmarkId,
    int population = 0,
    Map<String, int> personCounts = const {},
    List<String> resourceIds = const [],
  }) : population = population < 0 ? 0 : population,
       personCounts = Map.unmodifiable(<String, int>{
         for (final entry in personCounts.entries)
           if (entry.key.isNotEmpty && entry.value > 0) entry.key: entry.value,
       }),
       resourceIds = List.unmodifiable(<String>[
         for (final id in resourceIds)
           if (id.isNotEmpty) id,
       ]);

  final String id;

  /// The World landmark this profile describes.
  final String landmarkId;

  /// How many people live here.
  final int population;

  /// How many of each person type live here, by person type id.
  final Map<String, int> personCounts;

  /// What this city produces, by resource type id.
  final List<String> resourceIds;

  EconomyLocation copyWith({
    String? id,
    String? landmarkId,
    int? population,
    Map<String, int>? personCounts,
    List<String>? resourceIds,
  }) => EconomyLocation(
    id: id ?? this.id,
    landmarkId: landmarkId ?? this.landmarkId,
    population: population ?? this.population,
    personCounts: personCounts ?? this.personCounts,
    resourceIds: resourceIds ?? this.resourceIds,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'landmarkId': landmarkId,
    'population': population,
    if (personCounts.isNotEmpty) 'personCounts': personCounts,
    if (resourceIds.isNotEmpty) 'resourceIds': resourceIds,
  };

  static EconomyLocation? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final landmarkId = _string(json['landmarkId']);
    if (id.isEmpty || landmarkId.isEmpty) return null;
    return EconomyLocation(
      id: id,
      landmarkId: landmarkId,
      population: _int(json['population']) ?? 0,
      personCounts: _counts(json['personCounts']),
      resourceIds: _stringList(json['resourceIds']),
    );
  }
}

/// A trade route between two cities, drawn on the map as a curve.
///
/// [controlPoints] are two `[u, v]` pairs in the unit square of the
/// equirectangular map, which keeps the curve stable if the map image is
/// replaced by one of different pixel dimensions.
@immutable
class TradeRoute {
  TradeRoute({
    required this.id,
    required this.fromLandmarkId,
    required this.toLandmarkId,
    this.resourceId,
    List<List<double>> controlPoints = const [],
  }) : controlPoints = List.unmodifiable(<List<double>>[
         for (final point in controlPoints)
           if (point.length >= 2 && point[0].isFinite && point[1].isFinite)
             List<double>.unmodifiable(<double>[
               point[0].clamp(0.0, 1.0),
               point[1].clamp(0.0, 1.0),
             ]),
       ]);

  final String id;
  final String fromLandmarkId;
  final String toLandmarkId;

  /// What travels this route, or null for whatever the cities produce.
  final String? resourceId;

  final List<List<double>> controlPoints;

  TradeRoute copyWith({
    String? id,
    String? fromLandmarkId,
    String? toLandmarkId,
    String? resourceId,
    bool clearResourceId = false,
    List<List<double>>? controlPoints,
  }) => TradeRoute(
    id: id ?? this.id,
    fromLandmarkId: fromLandmarkId ?? this.fromLandmarkId,
    toLandmarkId: toLandmarkId ?? this.toLandmarkId,
    resourceId: clearResourceId ? null : (resourceId ?? this.resourceId),
    controlPoints: controlPoints ?? this.controlPoints,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'from': fromLandmarkId,
    'to': toLandmarkId,
    'resourceId': ?resourceId,
    if (controlPoints.isNotEmpty) 'controlPoints': controlPoints,
  };

  static TradeRoute? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final from = _string(json['from']);
    final to = _string(json['to']);
    if (id.isEmpty || from.isEmpty || to.isEmpty || from == to) return null;
    return TradeRoute(
      id: id,
      fromLandmarkId: from,
      toLandmarkId: to,
      resourceId: _nonEmpty(json['resourceId']),
      controlPoints: _points(json['controlPoints']),
    );
  }
}

/// A resource deposit on the map that workers travel to and collect from.
@immutable
class ResourceNode {
  ResourceNode({
    required this.id,
    required this.resourceId,
    required double latitude,
    required double longitude,
    this.homeLandmarkId,
  }) : latitude = latitude.isFinite ? latitude.clamp(-90.0, 90.0) : 0.0,
       longitude = longitude.isFinite ? longitude.clamp(-180.0, 180.0) : 0.0;

  final String id;

  /// Which resource type this deposit yields.
  final String resourceId;

  final double latitude;
  final double longitude;

  /// The city whose workers work this deposit, when one is assigned.
  final String? homeLandmarkId;

  ResourceNode copyWith({
    String? id,
    String? resourceId,
    double? latitude,
    double? longitude,
    String? homeLandmarkId,
    bool clearHomeLandmark = false,
  }) => ResourceNode(
    id: id ?? this.id,
    resourceId: resourceId ?? this.resourceId,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    homeLandmarkId: clearHomeLandmark
        ? null
        : (homeLandmarkId ?? this.homeLandmarkId),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'resourceId': resourceId,
    'latitude': latitude,
    'longitude': longitude,
    'homeLandmarkId': ?homeLandmarkId,
  };

  static ResourceNode? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final resourceId = _string(json['resourceId']);
    final latitude = _optionalDouble(json['latitude']);
    final longitude = _optionalDouble(json['longitude']);
    if (id.isEmpty || resourceId.isEmpty || latitude == null || longitude == null) {
      return null;
    }
    return ResourceNode(
      id: id,
      resourceId: resourceId,
      latitude: latitude,
      longitude: longitude,
      homeLandmarkId: _nonEmpty(json['homeLandmarkId']),
    );
  }
}

/// Everything the Economy view owns, stored under `economy` in the World.
@immutable
class WorldEconomy {
  factory WorldEconomy({
    List<PersonType> personTypes = const [],
    List<ResourceType> resourceTypes = const [],
    List<EconomyLocation> locations = const [],
    List<TradeRoute> tradeRoutes = const [],
    List<ResourceNode> resourceNodes = const [],
  }) => WorldEconomy._(
    personTypes: List.unmodifiable(personTypes),
    resourceTypes: List.unmodifiable(resourceTypes),
    locations: List.unmodifiable(locations),
    tradeRoutes: List.unmodifiable(tradeRoutes),
    resourceNodes: List.unmodifiable(resourceNodes),
  );

  const WorldEconomy._({
    this.personTypes = const [],
    this.resourceTypes = const [],
    this.locations = const [],
    this.tradeRoutes = const [],
    this.resourceNodes = const [],
  });

  static const WorldEconomy empty = WorldEconomy._();

  /// The three resources a world starts with. Custom ones are added beside
  /// them and are ordinary [ResourceType]s.
  static const List<ResourceType> builtInResources = <ResourceType>[
    ResourceType(id: 'stone', name: 'Stone', color: 'slate'),
    ResourceType(id: 'timber', name: 'Timber', color: 'green'),
    ResourceType(id: 'gold', name: 'Gold', color: 'amber'),
  ];

  /// A world's starting economy: no people and no cities, but the three
  /// resources the map lets workers collect without setting anything up.
  factory WorldEconomy.seeded() =>
      WorldEconomy(resourceTypes: builtInResources);

  final List<PersonType> personTypes;
  final List<ResourceType> resourceTypes;
  final List<EconomyLocation> locations;
  final List<TradeRoute> tradeRoutes;
  final List<ResourceNode> resourceNodes;

  bool get isEmpty =>
      personTypes.isEmpty &&
      resourceTypes.isEmpty &&
      locations.isEmpty &&
      tradeRoutes.isEmpty &&
      resourceNodes.isEmpty;

  EconomyLocation? locationForLandmark(String landmarkId) {
    for (final location in locations) {
      if (location.landmarkId == landmarkId) return location;
    }
    return null;
  }

  PersonType? personType(String id) => _firstWhere(personTypes, (t) => t.id == id);

  ResourceType? resourceType(String id) =>
      _firstWhere(resourceTypes, (t) => t.id == id);

  WorldEconomy copyWith({
    List<PersonType>? personTypes,
    List<ResourceType>? resourceTypes,
    List<EconomyLocation>? locations,
    List<TradeRoute>? tradeRoutes,
    List<ResourceNode>? resourceNodes,
  }) => WorldEconomy(
    personTypes: personTypes ?? this.personTypes,
    resourceTypes: resourceTypes ?? this.resourceTypes,
    locations: locations ?? this.locations,
    tradeRoutes: tradeRoutes ?? this.tradeRoutes,
    resourceNodes: resourceNodes ?? this.resourceNodes,
  );

  /// Adds or replaces the profile for a landmark.
  WorldEconomy withLocation(EconomyLocation location) => copyWith(
    locations: [
      for (final existing in locations)
        if (existing.landmarkId != location.landmarkId) existing,
      location,
    ],
  );

  /// Removes a city's profile and every route or node that pointed at it.
  /// The landmark itself is removed by the World, not here.
  WorldEconomy withoutLandmark(String landmarkId) => copyWith(
    locations: [
      for (final location in locations)
        if (location.landmarkId != landmarkId) location,
    ],
    tradeRoutes: [
      for (final route in tradeRoutes)
        if (route.fromLandmarkId != landmarkId &&
            route.toLandmarkId != landmarkId)
          route,
    ],
    resourceNodes: [
      for (final node in resourceNodes)
        if (node.homeLandmarkId != landmarkId) node,
    ],
  );

  WorldEconomy withPersonType(PersonType personType) => copyWith(
    personTypes: [
      for (final existing in personTypes)
        if (existing.id != personType.id) existing,
      personType,
    ],
  );

  /// Removes a person type everywhere it is used.
  WorldEconomy withoutPersonType(String personTypeId) => copyWith(
    personTypes: [
      for (final personType in personTypes)
        if (personType.id != personTypeId) personType,
    ],
    locations: [
      for (final location in locations)
        location.copyWith(
          personCounts: {
            for (final entry in location.personCounts.entries)
              if (entry.key != personTypeId) entry.key: entry.value,
          },
        ),
    ],
  );

  WorldEconomy withResourceType(ResourceType resourceType) => copyWith(
    resourceTypes: [
      for (final existing in resourceTypes)
        if (existing.id != resourceType.id) existing,
      resourceType,
    ],
  );

  /// Removes a resource type from the registry, every city, every node and
  /// every route that named it.
  WorldEconomy withoutResourceType(String resourceTypeId) => copyWith(
    resourceTypes: [
      for (final resourceType in resourceTypes)
        if (resourceType.id != resourceTypeId) resourceType,
    ],
    locations: [
      for (final location in locations)
        location.copyWith(
          resourceIds: [
            for (final id in location.resourceIds)
              if (id != resourceTypeId) id,
          ],
        ),
    ],
    resourceNodes: [
      for (final node in resourceNodes)
        if (node.resourceId != resourceTypeId) node,
    ],
    tradeRoutes: [
      for (final route in tradeRoutes)
        if (route.resourceId == resourceTypeId)
          route.copyWith(clearResourceId: true)
        else
          route,
    ],
  );

  WorldEconomy withTradeRoute(TradeRoute route) => copyWith(
    tradeRoutes: [
      for (final existing in tradeRoutes)
        if (existing.id != route.id) existing,
      route,
    ],
  );

  WorldEconomy withoutTradeRoute(String routeId) => copyWith(
    tradeRoutes: [
      for (final route in tradeRoutes)
        if (route.id != routeId) route,
    ],
  );

  WorldEconomy withResourceNode(ResourceNode node) => copyWith(
    resourceNodes: [
      for (final existing in resourceNodes)
        if (existing.id != node.id) existing,
      node,
    ],
  );

  WorldEconomy withoutResourceNode(String nodeId) => copyWith(
    resourceNodes: [
      for (final node in resourceNodes)
        if (node.id != nodeId) node,
    ],
  );

  Map<String, Object?> toJson() => {
    if (personTypes.isNotEmpty)
      'personTypes': [for (final type in personTypes) type.toJson()],
    if (resourceTypes.isNotEmpty)
      'resourceTypes': [for (final type in resourceTypes) type.toJson()],
    if (locations.isNotEmpty)
      'locations': [for (final location in locations) location.toJson()],
    if (tradeRoutes.isNotEmpty)
      'tradeRoutes': [for (final route in tradeRoutes) route.toJson()],
    if (resourceNodes.isNotEmpty)
      'resourceNodes': [for (final node in resourceNodes) node.toJson()],
  };

  /// Tolerant by design: a World with no `economy` — every file written before
  /// format 4 — reads as an empty one rather than failing.
  static WorldEconomy fromJson(Object? value) {
    if (value is! Map) return WorldEconomy.empty;
    final json = Map<String, Object?>.from(value);
    return WorldEconomy(
      personTypes: _parseList(json['personTypes'], PersonType.fromJson),
      resourceTypes: _parseList(json['resourceTypes'], ResourceType.fromJson),
      locations: _parseList(json['locations'], EconomyLocation.fromJson),
      tradeRoutes: _parseList(json['tradeRoutes'], TradeRoute.fromJson),
      resourceNodes: _parseList(json['resourceNodes'], ResourceNode.fromJson),
    );
  }
}

T? _firstWhere<T>(List<T> values, bool Function(T) test) {
  for (final value in values) {
    if (test(value)) return value;
  }
  return null;
}

List<T> _parseList<T>(
  Object? value,
  T? Function(Map<String, Object?>) parse,
) {
  if (value is! List) return <T>[];
  final parsed = <T>[];
  for (final raw in value) {
    if (raw is! Map) continue;
    final item = parse(Map<String, Object?>.from(raw));
    if (item != null) parsed.add(item);
  }
  return parsed;
}

String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

String? _nonEmpty(Object? value) {
  final valueAsString = _string(value);
  return valueAsString.isEmpty ? null : valueAsString;
}

int? _int(Object? value) => switch (value) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s),
  _ => null,
};

double? _optionalDouble(Object? value) => switch (value) {
  final double d => d.isFinite ? d : null,
  final num n => n.isFinite ? n.toDouble() : null,
  final String s => switch (double.tryParse(s)) {
    final double d when d.isFinite => d,
    _ => null,
  },
  _ => null,
};

Map<String, int> _counts(Object? value) {
  if (value is! Map) return const {};
  final counts = <String, int>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String || key.isEmpty) continue;
    final count = _int(entry.value);
    if (count != null && count > 0) counts[key] = count;
  }
  return counts;
}

List<String> _stringList(Object? value) {
  if (value is! List) return const [];
  return <String>[
    for (final item in value)
      if (item is String && item.isNotEmpty) item,
  ];
}

List<List<double>> _points(Object? value) {
  if (value is! List) return const [];
  final points = <List<double>>[];
  for (final raw in value) {
    if (raw is! List || raw.length < 2) continue;
    final u = _optionalDouble(raw[0]);
    final v = _optionalDouble(raw[1]);
    if (u == null || v == null) continue;
    points.add(<double>[u.clamp(0.0, 1.0), v.clamp(0.0, 1.0)]);
  }
  return points;
}
