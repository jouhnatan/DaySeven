import 'dart:convert';

import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DaySeven3DModel', () {
    test('round-trips through JSON cleanly', () {
      final model = DaySeven3DModel(
        geometry: const PlanetGeometry(
          shape: 'sphere',
          radiusKm: 7200.0,
          flattening: 0.005,
          subdivisions: 128,
        ),
        astronomy: const PlanetAstronomy(
          axialTiltDeg: 14.5,
          rotationPeriodHours: 32.0,
          orbitPeriodDays: 410.0,
        ),
        environment: const PlanetEnvironment(
          atmosphere: PlanetAtmosphere(
            enabled: true,
            colorHex: '#A0C4FF',
            density: 1.2,
            altitudeKm: 120.0,
          ),
          ocean: PlanetOcean(
            enabled: true,
            seaLevel: 0.1,
            colorHex: '#0B3954',
            specularIntensity: 0.9,
          ),
          lighting: PlanetLighting(
            ambientIntensity: 0.3,
            sunColorHex: '#FFEAA7',
            sunAzimuthDeg: 60.0,
            sunElevationDeg: 45.0,
          ),
        ),
        layers: const [
          Model3DLayer(
            id: 'l-topo',
            name: 'Topography',
            type: Model3DLayerType.heightmap,
            assetId: 'heightmap.png',
            minElevationMeters: -8000,
            maxElevationMeters: 6500,
          ),
          Model3DLayer(
            id: 'l-color',
            name: 'Albedo Colors',
            type: Model3DLayerType.albedo,
            assetId: 'albedo.png',
            opacity: 0.85,
          ),
        ],
        landmarks: [
          Model3DLandmark(
            id: 'lm-1',
            name: 'Crown Citadel',
            latitude: 42.5,
            longitude: -71.2,
            elevationMeters: 450.0,
            category: 'city',
            color: 'amber',
            document: 'Places/Citadel.md',
            description: 'Capital of the High Realm',
          ),
        ],
        regions: [
          Model3DRegion(
            id: 'reg-1',
            name: 'The Sunken Vale',
            color: 'teal',
            document: 'Regions/Vale.md',
            coordinates: const [
              [10.0, 20.0],
              [15.0, 25.0],
              [12.0, 30.0],
            ],
          ),
        ],
      );

      final json = model.toJson();
      final jsonString = jsonEncode(json);
      final decoded = jsonDecode(jsonString) as Map<String, Object?>;
      final restored = DaySeven3DModel.fromJson(decoded);

      expect(restored.schema, kDaySeven3DModelSchema);
      expect(restored.geometry.radiusKm, 7200.0);
      expect(restored.geometry.flattening, 0.005);
      expect(restored.geometry.subdivisions, 128);

      expect(restored.astronomy.axialTiltDeg, 14.5);
      expect(restored.astronomy.rotationPeriodHours, 32.0);
      expect(restored.astronomy.orbitPeriodDays, 410.0);

      expect(restored.environment.atmosphere.enabled, isTrue);
      expect(restored.environment.atmosphere.colorHex, '#A0C4FF');
      expect(restored.environment.ocean.seaLevel, 0.1);
      expect(restored.environment.lighting.sunAzimuthDeg, 60.0);

      expect(restored.layers.length, 2);
      expect(restored.layers[0].type, Model3DLayerType.heightmap);
      expect(restored.layers[0].minElevationMeters, -8000);
      expect(restored.layers[1].type, Model3DLayerType.albedo);
      expect(restored.layers[1].opacity, 0.85);

      expect(restored.landmarks.single.name, 'Crown Citadel');
      expect(restored.landmarks.single.latitude, 42.5);
      expect(restored.landmarks.single.document, 'Places/Citadel.md');

      expect(restored.regions.single.name, 'The Sunken Vale');
      expect(restored.regions.single.coordinates.length, 3);
      expect(restored.regions.single.coordinates[0], [10.0, 20.0]);
    });

    test('rejection of unsupported newer \$schema versions prevents data loss', () {
      expect(
        () => DaySeven3DModel.fromJson({
          '\$schema': 'https://dayseven.app/schemas/v2/world-model-3d.json',
        }),
        throwsA(isA<FormatException>()),
      );
    });

    test('collections are deeply immutable', () {
      final model = DaySeven3DModel(
        layers: [
          const Model3DLayer(
            id: 'l1',
            name: 'Layer 1',
            assetId: 'asset1.png',
          ),
        ],
        landmarks: [
          Model3DLandmark(
            id: 'lm1',
            name: 'Point',
            latitude: 10,
            longitude: 20,
          ),
        ],
        regions: [
          Model3DRegion(
            id: 'reg1',
            name: 'Region',
            coordinates: [
              [10.0, 20.0],
            ],
          ),
        ],
      );

      expect(
        () => model.layers.add(
          const Model3DLayer(id: 'l2', name: 'L2', assetId: 'a2.png'),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => model.landmarks.add(
          Model3DLandmark(id: 'lm2', name: 'P2', latitude: 0, longitude: 0),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => model.regions.add(Model3DRegion(id: 'r2', name: 'R2')),
        throwsUnsupportedError,
      );
      expect(
        () => model.regions.single.coordinates.first.add(30.0),
        throwsUnsupportedError,
      );
    });

    test('tolerates missing or hand-edited fields with safe fallbacks', () {
      final restored = DaySeven3DModel.fromJson(const {});

      expect(restored.schema, kDaySeven3DModelSchema);
      expect(restored.geometry.radiusKm, 6371.0);
      expect(restored.geometry.shape, 'sphere');
      expect(restored.astronomy.axialTiltDeg, 23.44);
      expect(restored.environment.atmosphere.enabled, isTrue);
      expect(restored.environment.ocean.enabled, isTrue);
      expect(restored.layers, isEmpty);
      expect(restored.landmarks, isEmpty);
      expect(restored.regions, isEmpty);
    });

    test('clamps landmark coordinates and handles non-finite numbers safely', () {
      final landmark = Model3DLandmark(
        id: 'lm-clamp',
        name: 'Far Outpost',
        latitude: 120.0,
        longitude: -240.0,
      );

      expect(landmark.latitude, 90.0);
      expect(landmark.longitude, -180.0);

      final nanLandmark = Model3DLandmark(
        id: 'lm-nan',
        name: 'Void Outpost',
        latitude: double.nan,
        longitude: double.infinity,
      );

      expect(nanLandmark.latitude, 0.0);
      expect(nanLandmark.longitude, 0.0);
    });
  });
}
