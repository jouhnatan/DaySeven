import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';
import 'package:dayseven/features/world/export/world_3d_exporter.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('world_3d_exporter_test');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  final testModel = DaySeven3DModel(
    geometry: const PlanetGeometry(radiusKm: 6400.0, flattening: 0.005),
    astronomy: const PlanetAstronomy(axialTiltDeg: 24.5),
    environment: const PlanetEnvironment(
      atmosphere: PlanetAtmosphere(enabled: true, density: 0.9),
      ocean: PlanetOcean(enabled: true, seaLevel: 0.1),
      lighting: PlanetLighting(sunAzimuthDeg: 60.0, sunElevationDeg: 30.0),
    ),
    layers: const [
      Model3DLayer(
        id: 'l-1',
        name: 'Topography',
        type: Model3DLayerType.heightmap,
        assetId: 'heightmap.png',
        visible: true,
      ),
    ],
    landmarks: [
      Model3DLandmark(
        id: 'lm-1',
        name: 'Highpass Citadel',
        latitude: 12.34,
        longitude: -45.67,
        category: 'fortress',
        document: 'Places/Highpass.md',
      ),
    ],
    regions: [
      Model3DRegion(
        id: 'reg-1',
        name: 'Whispering Plains',
        color: '#38bdf8',
        document: 'Places/Plains.md',
        // Deliberately unclosed 3-point polygon to test automatic RFC 7946 closure
        coordinates: [
          [-45.0, 10.0],
          [-40.0, 10.0],
          [-40.0, 15.0],
        ],
      ),
      Model3DRegion(
        id: 'reg-degenerate',
        name: 'Line Segment',
        // Fewer than 3 vertices -> degenerate polygon
        coordinates: [
          [0.0, 0.0],
          [1.0, 1.0],
        ],
      ),
      Model3DRegion(
        id: 'reg-degenerate-same-vertices',
        name: 'Duplicate Vertices',
        // 3 coordinate entries, but only 2 distinct vertices
        coordinates: [
          [0.0, 0.0],
          [0.0, 0.0],
          [1.0, 1.0],
        ],
      ),
      Model3DRegion(
        id: 'reg-degenerate-signed-zero',
        name: 'Signed Zero Duplicate Vertices',
        // 3 coordinate entries, but [0.0, 0.0] and [-0.0, 0.0] represent the same vertex
        coordinates: [
          [0.0, 0.0],
          [-0.0, 0.0],
          [1.0, 1.0],
        ],
      ),
    ],
  );

  test('exportModelJson exports valid JSON conforming to schema', () {
    const exporter = World3DExporter();
    final jsonStr = exporter.exportModelJson(testModel, worldTitle: 'Aethel');

    final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
    expect(
      decoded['\$schema'],
      'https://dayseven.app/schemas/v1/world-model-3d.json',
    );
    expect(decoded['title'], 'Aethel');
    expect(decoded['geometry']['radiusKm'], 6400.0);
    expect(decoded['astronomy']['axialTiltDeg'], 24.5);
    expect(decoded['environment']['atmosphere']['enabled'], isTrue);
    expect(decoded['environment']['ocean']['seaLevel'], 0.1);

    // Verify round-trip back into DaySeven3DModel
    final roundTripped = DaySeven3DModel.fromJson(decoded);
    expect(roundTripped.geometry.radiusKm, 6400.0);
    expect(roundTripped.landmarks.length, 1);
    expect(roundTripped.landmarks.first.name, 'Highpass Citadel');
    expect(roundTripped.regions.length, 4);
    expect(roundTripped.regions.first.name, 'Whispering Plains');
  });

  test('exportGeoJson conforms to RFC 7946 and closes polygon rings', () {
    const exporter = World3DExporter();
    final geoJsonStr = exporter.exportGeoJson(testModel, worldTitle: 'Aethel');

    final decoded = jsonDecode(geoJsonStr) as Map<String, dynamic>;
    expect(decoded['type'], 'FeatureCollection');
    expect(decoded['name'], 'Aethel Landmarks & Regions');

    final features = decoded['features'] as List<dynamic>;
    // All degenerate regions (< 3 vertices, duplicate vertices, signed-zero duplicates) are omitted
    expect(features.length, 2);
    final featureIds = features.map((f) => f['id']).toList();
    expect(featureIds, isNot(contains('reg-degenerate')));
    expect(featureIds, isNot(contains('reg-degenerate-same-vertices')));
    expect(featureIds, isNot(contains('reg-degenerate-signed-zero')));

    // Landmark Point Feature
    final pointFeature = features[0] as Map<String, dynamic>;
    expect(pointFeature['type'], 'Feature');
    expect(pointFeature['id'], 'lm-1');
    expect(pointFeature['geometry']['type'], 'Point');
    // GeoJSON coordinate order: [longitude, latitude]
    expect(pointFeature['geometry']['coordinates'], [-45.67, 12.34]);
    expect(pointFeature['properties']['name'], 'Highpass Citadel');
    expect(pointFeature['properties']['document'], 'Places/Highpass.md');

    // Region Polygon Feature
    final polygonFeature = features[1] as Map<String, dynamic>;
    expect(polygonFeature['type'], 'Feature');
    expect(polygonFeature['id'], 'reg-1');
    expect(polygonFeature['geometry']['type'], 'Polygon');
    final polygonRings =
        polygonFeature['geometry']['coordinates'] as List<dynamic>;
    expect(polygonRings.length, 1);
    final ring = polygonRings.first as List<dynamic>;
    // RFC 7946 ring is automatically closed with 4 points
    expect(ring.length, 4);
    expect(ring.first, [-45.0, 10.0]);
    expect(ring.last, [-45.0, 10.0]);
    expect(polygonFeature['properties']['name'], 'Whispering Plains');
    expect(polygonFeature['properties']['color'], '#38bdf8');
  });

  test('exportStandaloneThreeJsHtml produces 100% offline self-contained WebGL viewer', () {
    const exporter = World3DExporter();
    final html = exporter.exportStandaloneThreeJsHtml(
      testModel,
      worldTitle: 'Aethel',
    );

    expect(html, contains('<!DOCTYPE html>'));
    expect(html, contains('<title>Aethel — DaySeven 3D Viewer</title>'));
    // Truly self-contained: no external script tags or stylesheets
    expect(html, isNot(contains('<script src')));
    expect(html, isNot(contains('<link rel="stylesheet"')));
    expect(html, isNot(contains('unpkg.com')));
    expect(html, contains('<canvas id="gl-canvas"></canvas>'));
    expect(
      html,
      contains('<script id="world-metadata" type="application/json">'),
    );
    expect(
      html,
      contains('<script id="world-geojson" type="application/json">'),
    );
    expect(html, contains('Highpass Citadel'));
    expect(html, contains('6400 km'));
  });

  test('escapes HTML markup and script tags against injection', () {
    const exporter = World3DExporter();
    final maliciousModel = DaySeven3DModel(
      landmarks: [
        Model3DLandmark(
          id: 'lm-xss',
          name: '</script><script>alert("xss")</script>',
          latitude: 0.0,
          longitude: 0.0,
        ),
        Model3DLandmark(
          id: 'lm-xss-dom',
          name: '<img src=x onerror=alert(1)>',
          latitude: 10.0,
          longitude: 20.0,
        ),
      ],
    );

    final html = exporter.exportStandaloneThreeJsHtml(
      maliciousModel,
      worldTitle: '<b>Danger & Evil</b>',
    );

    // HTML title and h1 are escaped
    expect(html, contains('&lt;b&gt;Danger &amp; Evil&lt;/b&gt;'));
    expect(html, isNot(contains('<b>Danger & Evil</b>')));

    // Script injection inside JSON is safely escaped with \u003c and \u003e
    expect(html, isNot(contains('</script><script>')));
    expect(html, contains(r'\u003c/script\u003e\u003cscript\u003e'));

    // Runtime DOM injection safety: pin labels built safely via textContent without innerHTML
    expect(html, isNot(contains('innerHTML')));
    expect(html, contains('labelEl.textContent = lm.name;'));
  });

  test('writes export files to disk correctly', () async {
    const exporter = World3DExporter();
    final jsonFile = File('${tempDir.path}/aethel.json');
    final geoJsonFile = File('${tempDir.path}/aethel.geojson');
    final htmlFile = File('${tempDir.path}/aethel.html');

    await exporter.exportModelJsonFile(
      testModel,
      jsonFile,
      worldTitle: 'Aethel',
    );
    await exporter.exportGeoJsonFile(
      testModel,
      geoJsonFile,
      worldTitle: 'Aethel',
    );
    await exporter.exportThreeJsHtmlFile(
      testModel,
      htmlFile,
      worldTitle: 'Aethel',
    );

    expect(await jsonFile.exists(), isTrue);
    expect(await geoJsonFile.exists(), isTrue);
    expect(await htmlFile.exists(), isTrue);

    final jsonContent = await jsonFile.readAsString();
    expect(
      jsonContent,
      contains('https://dayseven.app/schemas/v1/world-model-3d.json'),
    );

    final geoJsonContent = await geoJsonFile.readAsString();
    expect(geoJsonContent, contains('FeatureCollection'));

    final htmlContent = await htmlFile.readAsString();
    expect(htmlContent, contains('<!DOCTYPE html>'));
  });
}
