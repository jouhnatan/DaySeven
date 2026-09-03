/// The native DaySeven 3D model metadata stored in a `.unearth` file.
///
/// Designed to be human-readable and standard JSON so it can be exported and
/// manipulated in third-party 3D tools and libraries (Blender, Godot, Three.js,
/// QGIS).
library;

import 'package:flutter/foundation.dart';

/// The official schema identifier for DaySeven 3D world models.
const String kDaySeven3DModelSchema =
    'https://dayseven.app/schemas/v1/world-model-3d.json';

/// The root 3D model definition for a world.
@immutable
class DaySeven3DModel {
  DaySeven3DModel({
    this.schema = kDaySeven3DModelSchema,
    this.geometry = const PlanetGeometry(),
    this.astronomy = const PlanetAstronomy(),
    this.environment = const PlanetEnvironment(),
    List<Model3DLayer> layers = const [],
    List<Model3DLandmark> landmarks = const [],
    List<Model3DRegion> regions = const [],
  })  : layers = List.unmodifiable(layers),
        landmarks = List.unmodifiable(landmarks),
        regions = List.unmodifiable(regions);

  final String schema;
  final PlanetGeometry geometry;
  final PlanetAstronomy astronomy;
  final PlanetEnvironment environment;
  final List<Model3DLayer> layers;
  final List<Model3DLandmark> landmarks;
  final List<Model3DRegion> regions;

  DaySeven3DModel copyWith({
    String? schema,
    PlanetGeometry? geometry,
    PlanetAstronomy? astronomy,
    PlanetEnvironment? environment,
    List<Model3DLayer>? layers,
    List<Model3DLandmark>? landmarks,
    List<Model3DRegion>? regions,
  }) => DaySeven3DModel(
    schema: schema ?? this.schema,
    geometry: geometry ?? this.geometry,
    astronomy: astronomy ?? this.astronomy,
    environment: environment ?? this.environment,
    layers: layers ?? this.layers,
    landmarks: landmarks ?? this.landmarks,
    regions: regions ?? this.regions,
  );

  Map<String, Object?> toJson() => {
    '\$schema': schema,
    'geometry': geometry.toJson(),
    'astronomy': astronomy.toJson(),
    'environment': environment.toJson(),
    if (layers.isNotEmpty) 'layers': [for (final l in layers) l.toJson()],
    if (landmarks.isNotEmpty)
      'landmarks': [for (final lm in landmarks) lm.toJson()],
    if (regions.isNotEmpty) 'regions': [for (final r in regions) r.toJson()],
  };

  static DaySeven3DModel fromJson(Map<String, Object?> json) {
    final declaredSchema = _string(json['\$schema']);
    if (declaredSchema.isNotEmpty && declaredSchema != kDaySeven3DModelSchema) {
      // If a future version schema is passed (e.g. /v2/), decline rather than discard unknown fields.
      if (declaredSchema.contains('/schemas/v') &&
          !declaredSchema.contains('/v1/')) {
        throw const FormatException(
          'That 3D model was written against a newer schema version. '
          'Update DaySeven before opening it to avoid losing data.',
        );
      }
    }

    final layers = <Model3DLayer>[];
    final rawLayers = json['layers'];
    if (rawLayers is List) {
      for (final raw in rawLayers) {
        if (raw is Map) {
          final layer = Model3DLayer.fromJson(Map<String, Object?>.from(raw));
          if (layer != null) layers.add(layer);
        }
      }
    }

    final landmarks = <Model3DLandmark>[];
    final rawLandmarks = json['landmarks'];
    if (rawLandmarks is List) {
      for (final raw in rawLandmarks) {
        if (raw is Map) {
          final landmark = Model3DLandmark.fromJson(
            Map<String, Object?>.from(raw),
          );
          if (landmark != null) landmarks.add(landmark);
        }
      }
    }

    final regions = <Model3DRegion>[];
    final rawRegions = json['regions'];
    if (rawRegions is List) {
      for (final raw in rawRegions) {
        if (raw is Map) {
          final region = Model3DRegion.fromJson(Map<String, Object?>.from(raw));
          if (region != null) regions.add(region);
        }
      }
    }

    return DaySeven3DModel(
      schema: declaredSchema.isEmpty ? kDaySeven3DModelSchema : declaredSchema,
      geometry: PlanetGeometry.fromJson(_map(json['geometry'])),
      astronomy: PlanetAstronomy.fromJson(_map(json['astronomy'])),
      environment: PlanetEnvironment.fromJson(_map(json['environment'])),
      layers: layers,
      landmarks: landmarks,
      regions: regions,
    );
  }
}

/// Physical shape parameters for the celestial body.
@immutable
class PlanetGeometry {
  const PlanetGeometry({
    this.shape = 'sphere',
    this.radiusKm = 6371.0,
    this.flattening = 0.00335,
    this.subdivisions = 64,
  });

  /// The geometric base shape ('sphere', 'ellipsoid', etc.).
  final String shape;

  /// Equatorial radius in kilometres. Default matches Earth (6371.0 km).
  final double radiusKm;

  /// Oblateness ratio `(a - b) / a`. Earth is ~0.00335.
  final double flattening;

  /// Mesh subdivision level for UV-sphere generation.
  final int subdivisions;

  PlanetGeometry copyWith({
    String? shape,
    double? radiusKm,
    double? flattening,
    int? subdivisions,
  }) => PlanetGeometry(
    shape: shape ?? this.shape,
    radiusKm: radiusKm ?? this.radiusKm,
    flattening: flattening ?? this.flattening,
    subdivisions: subdivisions ?? this.subdivisions,
  );

  Map<String, Object?> toJson() => {
    'shape': shape,
    'radiusKm': radiusKm,
    'flattening': flattening,
    'subdivisions': subdivisions,
  };

  static PlanetGeometry fromJson(Map<String, Object?> json) => PlanetGeometry(
    shape: _string(json['shape'], fallback: 'sphere'),
    radiusKm: _double(json['radiusKm'], fallback: 6371.0),
    flattening: _double(json['flattening'], fallback: 0.00335),
    subdivisions: _int(json['subdivisions'], fallback: 64),
  );
}

/// Planetary rotation and orbit characteristics.
@immutable
class PlanetAstronomy {
  const PlanetAstronomy({
    this.axialTiltDeg = 23.44,
    this.rotationPeriodHours = 24.0,
    this.orbitPeriodDays = 365.25,
  });

  /// Axial obliquity in degrees.
  final double axialTiltDeg;

  /// Sidereal day length in solar hours.
  final double rotationPeriodHours;

  /// Orbital year length in local solar days.
  final double orbitPeriodDays;

  PlanetAstronomy copyWith({
    double? axialTiltDeg,
    double? rotationPeriodHours,
    double? orbitPeriodDays,
  }) => PlanetAstronomy(
    axialTiltDeg: axialTiltDeg ?? this.axialTiltDeg,
    rotationPeriodHours: rotationPeriodHours ?? this.rotationPeriodHours,
    orbitPeriodDays: orbitPeriodDays ?? this.orbitPeriodDays,
  );

  Map<String, Object?> toJson() => {
    'axialTiltDeg': axialTiltDeg,
    'rotationPeriodHours': rotationPeriodHours,
    'orbitPeriodDays': orbitPeriodDays,
  };

  static PlanetAstronomy fromJson(Map<String, Object?> json) => PlanetAstronomy(
    axialTiltDeg: _double(json['axialTiltDeg'], fallback: 23.44),
    rotationPeriodHours: _double(json['rotationPeriodHours'], fallback: 24.0),
    orbitPeriodDays: _double(json['orbitPeriodDays'], fallback: 365.25),
  );
}

/// Atmospheric and ocean visual properties.
@immutable
class PlanetEnvironment {
  const PlanetEnvironment({
    this.atmosphere = const PlanetAtmosphere(),
    this.ocean = const PlanetOcean(),
    this.lighting = const PlanetLighting(),
  });

  final PlanetAtmosphere atmosphere;
  final PlanetOcean ocean;
  final PlanetLighting lighting;

  PlanetEnvironment copyWith({
    PlanetAtmosphere? atmosphere,
    PlanetOcean? ocean,
    PlanetLighting? lighting,
  }) => PlanetEnvironment(
    atmosphere: atmosphere ?? this.atmosphere,
    ocean: ocean ?? this.ocean,
    lighting: lighting ?? this.lighting,
  );

  Map<String, Object?> toJson() => {
    'atmosphere': atmosphere.toJson(),
    'ocean': ocean.toJson(),
    'lighting': lighting.toJson(),
  };

  static PlanetEnvironment fromJson(Map<String, Object?> json) =>
      PlanetEnvironment(
        atmosphere: PlanetAtmosphere.fromJson(_map(json['atmosphere'])),
        ocean: PlanetOcean.fromJson(_map(json['ocean'])),
        lighting: PlanetLighting.fromJson(_map(json['lighting'])),
      );
}

/// Atmosphere scattering and cloud configuration.
@immutable
class PlanetAtmosphere {
  const PlanetAtmosphere({
    this.enabled = true,
    this.colorHex = '#88B8F8',
    this.density = 1.0,
    this.altitudeKm = 100.0,
  });

  final bool enabled;
  final String colorHex;
  final double density;
  final double altitudeKm;

  PlanetAtmosphere copyWith({
    bool? enabled,
    String? colorHex,
    double? density,
    double? altitudeKm,
  }) => PlanetAtmosphere(
    enabled: enabled ?? this.enabled,
    colorHex: colorHex ?? this.colorHex,
    density: density ?? this.density,
    altitudeKm: altitudeKm ?? this.altitudeKm,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'colorHex': colorHex,
    'density': density,
    'altitudeKm': altitudeKm,
  };

  static PlanetAtmosphere fromJson(Map<String, Object?> json) =>
      PlanetAtmosphere(
        enabled: _bool(json['enabled'], fallback: true),
        colorHex: _string(json['colorHex'], fallback: '#88B8F8'),
        density: _double(json['density'], fallback: 1.0),
        altitudeKm: _double(json['altitudeKm'], fallback: 100.0),
      );
}

/// Planetary ocean and hydrosphere parameters.
@immutable
class PlanetOcean {
  const PlanetOcean({
    this.enabled = true,
    this.seaLevel = 0.0,
    this.colorHex = '#1A4B8C',
    this.specularIntensity = 0.8,
  });

  final bool enabled;
  final double seaLevel;
  final String colorHex;
  final double specularIntensity;

  PlanetOcean copyWith({
    bool? enabled,
    double? seaLevel,
    String? colorHex,
    double? specularIntensity,
  }) => PlanetOcean(
    enabled: enabled ?? this.enabled,
    seaLevel: seaLevel ?? this.seaLevel,
    colorHex: colorHex ?? this.colorHex,
    specularIntensity: specularIntensity ?? this.specularIntensity,
  );

  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'seaLevel': seaLevel,
    'colorHex': colorHex,
    'specularIntensity': specularIntensity,
  };

  static PlanetOcean fromJson(Map<String, Object?> json) => PlanetOcean(
    enabled: _bool(json['enabled'], fallback: true),
    seaLevel: _double(json['seaLevel'], fallback: 0.0),
    colorHex: _string(json['colorHex'], fallback: '#1A4B8C'),
    specularIntensity: _double(json['specularIntensity'], fallback: 0.8),
  );
}

/// Sunlight direction and ambient shading parameters.
@immutable
class PlanetLighting {
  const PlanetLighting({
    this.ambientIntensity = 0.25,
    this.sunColorHex = '#FFF9E8',
    this.sunAzimuthDeg = 45.0,
    this.sunElevationDeg = 25.0,
  });

  final double ambientIntensity;
  final String sunColorHex;
  final double sunAzimuthDeg;
  final double sunElevationDeg;

  PlanetLighting copyWith({
    double? ambientIntensity,
    String? sunColorHex,
    double? sunAzimuthDeg,
    double? sunElevationDeg,
  }) => PlanetLighting(
    ambientIntensity: ambientIntensity ?? this.ambientIntensity,
    sunColorHex: sunColorHex ?? this.sunColorHex,
    sunAzimuthDeg: sunAzimuthDeg ?? this.sunAzimuthDeg,
    sunElevationDeg: sunElevationDeg ?? this.sunElevationDeg,
  );

  Map<String, Object?> toJson() => {
    'ambientIntensity': ambientIntensity,
    'sunColorHex': sunColorHex,
    'sunAzimuthDeg': sunAzimuthDeg,
    'sunElevationDeg': sunElevationDeg,
  };

  static PlanetLighting fromJson(Map<String, Object?> json) => PlanetLighting(
    ambientIntensity: _double(json['ambientIntensity'], fallback: 0.25),
    sunColorHex: _string(json['sunColorHex'], fallback: '#FFF9E8'),
    sunAzimuthDeg: _double(json['sunAzimuthDeg'], fallback: 45.0),
    sunElevationDeg: _double(json['sunElevationDeg'], fallback: 25.0),
  );
}

/// The kind of texture layer in the 3D model stack.
enum Model3DLayerType {
  heightmap,
  albedo,
  normal,
  specular,
  roughness,
  clouds,
  biomes,
  nightLights;

  String get id => switch (this) {
    Model3DLayerType.heightmap => 'heightmap',
    Model3DLayerType.albedo => 'albedo',
    Model3DLayerType.normal => 'normal',
    Model3DLayerType.specular => 'specular',
    Model3DLayerType.roughness => 'roughness',
    Model3DLayerType.clouds => 'clouds',
    Model3DLayerType.biomes => 'biomes',
    Model3DLayerType.nightLights => 'night_lights',
  };

  String get label => switch (this) {
    Model3DLayerType.heightmap => 'Elevation (Heightmap)',
    Model3DLayerType.albedo => 'Surface Color (Albedo)',
    Model3DLayerType.normal => 'Normal Map',
    Model3DLayerType.specular => 'Specular Map',
    Model3DLayerType.roughness => 'Roughness Map',
    Model3DLayerType.clouds => 'Cloud Layer',
    Model3DLayerType.biomes => 'Biome Map',
    Model3DLayerType.nightLights => 'Night Lights',
  };

  static Model3DLayerType parse(Object? value) {
    final str = _string(value).toLowerCase();
    return switch (str) {
      'albedo' || 'diffuse' || 'color' => Model3DLayerType.albedo,
      'normal' => Model3DLayerType.normal,
      'specular' => Model3DLayerType.specular,
      'roughness' => Model3DLayerType.roughness,
      'clouds' => Model3DLayerType.clouds,
      'biomes' || 'biome' => Model3DLayerType.biomes,
      'night_lights' || 'nightlights' => Model3DLayerType.nightLights,
      _ => Model3DLayerType.heightmap,
    };
  }
}

/// One texture layer attached to the 3D model.
@immutable
class Model3DLayer {
  const Model3DLayer({
    required this.id,
    required this.name,
    this.type = Model3DLayerType.heightmap,
    required this.assetId,
    this.projection = 'equirectangular',
    this.visible = true,
    this.opacity = 1.0,
    this.minElevationMeters,
    this.maxElevationMeters,
  });

  final String id;
  final String name;
  final Model3DLayerType type;
  final String assetId;
  final String projection;
  final bool visible;
  final double opacity;
  final double? minElevationMeters;
  final double? maxElevationMeters;

  Model3DLayer copyWith({
    String? id,
    String? name,
    Model3DLayerType? type,
    String? assetId,
    String? projection,
    bool? visible,
    double? opacity,
    double? minElevationMeters,
    double? maxElevationMeters,
  }) => Model3DLayer(
    id: id ?? this.id,
    name: name ?? this.name,
    type: type ?? this.type,
    assetId: assetId ?? this.assetId,
    projection: projection ?? this.projection,
    visible: visible ?? this.visible,
    opacity: opacity ?? this.opacity,
    minElevationMeters: minElevationMeters ?? this.minElevationMeters,
    maxElevationMeters: maxElevationMeters ?? this.maxElevationMeters,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'type': type.id,
    'assetId': assetId,
    'projection': projection,
    'visible': visible,
    'opacity': opacity,
    'minElevationMeters': ?minElevationMeters,
    'maxElevationMeters': ?maxElevationMeters,
  };

  static Model3DLayer? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final assetId = _string(json['assetId']);
    if (id.isEmpty || assetId.isEmpty) return null;

    return Model3DLayer(
      id: id,
      name: _string(json['name'], fallback: 'Layer'),
      type: Model3DLayerType.parse(json['type']),
      assetId: assetId,
      projection: _string(json['projection'], fallback: 'equirectangular'),
      visible: _bool(json['visible'], fallback: true),
      opacity: _double(json['opacity'], fallback: 1.0),
      minElevationMeters: _optionalDouble(json['minElevationMeters']),
      maxElevationMeters: _optionalDouble(json['maxElevationMeters']),
    );
  }
}

/// A pin or point of interest placed on the 3D surface.
@immutable
class Model3DLandmark {
  Model3DLandmark({
    required this.id,
    required this.name,
    required double latitude,
    required double longitude,
    double elevationMeters = 0.0,
    this.category = 'city',
    this.color = 'amber',
    this.document,
    this.description,
  })  : latitude = latitude.isFinite ? latitude.clamp(-90.0, 90.0) : 0.0,
        longitude = longitude.isFinite ? longitude.clamp(-180.0, 180.0) : 0.0,
        elevationMeters = elevationMeters.isFinite ? elevationMeters : 0.0;

  final String id;
  final String name;

  /// Latitude in degrees, from -90.0 (South Pole) to +90.0 (North Pole).
  final double latitude;

  /// Longitude in degrees, from -180.0 to +180.0.
  final double longitude;

  /// Elevation in metres relative to sea level.
  final double elevationMeters;

  /// Functional category: 'city', 'mountain', 'ruin', 'landmark', 'port'.
  final String category;

  /// Accent colour key for rendering the pin.
  final String color;

  /// Optional relative path to a Markdown document in the Knowledge Base.
  final String? document;

  /// Short inline summary text.
  final String? description;

  Model3DLandmark copyWith({
    String? id,
    String? name,
    double? latitude,
    double? longitude,
    double? elevationMeters,
    String? category,
    String? color,
    String? document,
    String? description,
  }) => Model3DLandmark(
    id: id ?? this.id,
    name: name ?? this.name,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    elevationMeters: elevationMeters ?? this.elevationMeters,
    category: category ?? this.category,
    color: color ?? this.color,
    document: document ?? this.document,
    description: description ?? this.description,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    if (elevationMeters != 0.0) 'elevationMeters': elevationMeters,
    'category': category,
    'color': color,
    'document': ?document,
    'description': ?description,
  };

  static Model3DLandmark? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final name = _string(json['name']);
    final lat = _optionalDouble(json['latitude']);
    final lon = _optionalDouble(json['longitude']);
    if (id.isEmpty || name.isEmpty || lat == null || lon == null) return null;

    return Model3DLandmark(
      id: id,
      name: name,
      latitude: lat,
      longitude: lon,
      elevationMeters: _double(json['elevationMeters'], fallback: 0.0),
      category: _string(json['category'], fallback: 'city'),
      color: _string(json['color'], fallback: 'amber'),
      document: _optionalString(json['document']),
      description: _optionalString(json['description']),
    );
  }
}

/// A spherical polygon region (nation, biome, or territory) formatted according
/// to GeoJSON (RFC 7946) standard with `[longitude, latitude]` coordinate order.
@immutable
class Model3DRegion {
  Model3DRegion({
    required this.id,
    required this.name,
    this.color = 'teal',
    this.document,
    List<List<double>> coordinates = const [],
  }) : coordinates = List<List<double>>.unmodifiable([
         for (final pt in coordinates)
           if (pt.length >= 2 && pt[0].isFinite && pt[1].isFinite)
             List<double>.unmodifiable(<double>[
               pt[0].clamp(-180.0, 180.0), // longitude
               pt[1].clamp(-90.0, 90.0),   // latitude
             ]),
       ]);

  final String id;
  final String name;
  final String color;
  final String? document;

  /// Sequential `[longitude, latitude]` coordinate points outlining the boundary.
  final List<List<double>> coordinates;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'color': color,
    'document': ?document,
    if (coordinates.isNotEmpty) 'coordinates': coordinates,
  };

  static Model3DRegion? fromJson(Map<String, Object?> json) {
    final id = _string(json['id']);
    final name = _string(json['name']);
    if (id.isEmpty || name.isEmpty) return null;

    final coords = <List<double>>[];
    final rawCoords = json['coordinates'];
    if (rawCoords is List) {
      for (final pt in rawCoords) {
        if (pt is List && pt.length >= 2) {
          final lon = _optionalDouble(pt[0]);
          final lat = _optionalDouble(pt[1]);
          if (lon != null && lat != null) {
            coords.add([lon, lat]);
          }
        }
      }
    }

    return Model3DRegion(
      id: id,
      name: name,
      color: _string(json['color'], fallback: 'teal'),
      document: _optionalString(json['document']),
      coordinates: coords,
    );
  }
}

// ---------------------------------------------------------------------------
// Resilient JSON parsing helpers
// ---------------------------------------------------------------------------

String _string(Object? value, {String fallback = ''}) =>
    value is String ? value : fallback;

String? _optionalString(Object? value) {
  final str = _string(value);
  return str.isEmpty ? null : str;
}

double _double(Object? value, {double fallback = 0.0}) => switch (value) {
  final double d => d,
  final num n => n.toDouble(),
  final String s => double.tryParse(s) ?? fallback,
  _ => fallback,
};

double? _optionalDouble(Object? value) => switch (value) {
  final double d => d,
  final num n => n.toDouble(),
  final String s => double.tryParse(s),
  _ => null,
};

int _int(Object? value, {int fallback = 0}) => switch (value) {
  final int i => i,
  final num n => n.toInt(),
  final String s => int.tryParse(s) ?? fallback,
  _ => fallback,
};

bool _bool(Object? value, {bool fallback = false}) => switch (value) {
  final bool b => b,
  final String s => s.toLowerCase() == 'true',
  _ => fallback,
};

Map<String, Object?> _map(Object? value) =>
    value is Map ? Map<String, Object?>.from(value) : const <String, Object?>{};
