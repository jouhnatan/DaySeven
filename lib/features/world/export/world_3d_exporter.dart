/// Exporters for DaySeven 3D planet models to third-party tools and formats.
///
/// Supports:
/// 1. Standalone Model JSON (.json) conforming to schema v1 for Blender/Godot/custom tools.
/// 2. GeoJSON FeatureCollection (.geojson, RFC 7946) for landmarks & regions in GIS tools.
/// 3. Standalone WebGL 3D Viewer (.html) - 100% self-contained, offline-capable, with orbit controls.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dayseven/features/world/domain/dayseven_3d_model.dart';

/// Exports [DaySeven3DModel] metadata into third-party formats.
class World3DExporter {
  const World3DExporter();

  /// Exports [model] as pretty-printed JSON conforming to schema v1.
  String exportModelJson(DaySeven3DModel model, {String? worldTitle}) {
    final map = model.toJson();
    if (worldTitle != null && worldTitle.isNotEmpty) {
      map['title'] = worldTitle;
    }
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Exports [model] landmarks and regions as an RFC 7946 GeoJSON FeatureCollection.
  String exportGeoJson(DaySeven3DModel model, {String? worldTitle}) {
    final features = <Map<String, dynamic>>[];

    for (final landmark in model.landmarks) {
      features.add({
        'type': 'Feature',
        'id': landmark.id,
        'geometry': {
          'type': 'Point',
          // GeoJSON standard: [longitude, latitude]
          'coordinates': [landmark.longitude, landmark.latitude],
        },
        'properties': {
          'id': landmark.id,
          'name': landmark.name,
          'category': landmark.category,
          if (landmark.document != null) 'document': landmark.document,
          'latitude': landmark.latitude,
          'longitude': landmark.longitude,
          'elevationMeters': landmark.elevationMeters,
        },
      });
    }

    for (final region in model.regions) {
      if (region.coordinates.length < 3) continue;

      // RFC 7946 requires at least 3 distinct vertices to form a polygon surface.
      // Normalizes signed zeros (-0.0 -> 0.0) to ensure accurate spatial comparison.
      final distinctVertices = <(double, double)>{};
      for (final pt in region.coordinates) {
        if (pt.length >= 2) {
          final lon = pt[0] == 0.0 ? 0.0 : pt[0];
          final lat = pt[1] == 0.0 ? 0.0 : pt[1];
          distinctVertices.add((lon, lat));
        }
      }
      if (distinctVertices.length < 3) continue;

      final ring = <List<double>>[];
      for (final pt in region.coordinates) {
        ring.add([pt[0], pt[1]]);
      }

      // RFC 7946 linear ring must be closed: first and last positions must be identical
      final first = ring.first;
      final last = ring.last;
      if (first[0] != last[0] || first[1] != last[1]) {
        ring.add([first[0], first[1]]);
      }

      // Linear ring requires at least 4 positions (triangle + closing point)
      if (ring.length < 4) continue;

      features.add({
        'type': 'Feature',
        'id': region.id,
        'geometry': {
          'type': 'Polygon',
          'coordinates': [ring],
        },
        'properties': {
          'id': region.id,
          'name': region.name,
          'color': region.color,
          if (region.document != null) 'document': region.document,
        },
      });
    }

    final collection = {
      'type': 'FeatureCollection',
      if (worldTitle != null && worldTitle.isNotEmpty)
        'name': '$worldTitle Landmarks & Regions',
      'features': features,
    };

    return const JsonEncoder.withIndent('  ').convert(collection);
  }

  /// Exports a 100% self-contained, offline-capable HTML document with an
  /// embedded WebGL 3D globe viewer. Does not make external network requests.
  String exportStandaloneThreeJsHtml(
    DaySeven3DModel model, {
    String? worldTitle,
  }) {
    final title = worldTitle ?? 'DaySeven 3D World';
    final safeTitle = _escapeHtml(title);
    final metadataJson = _escapeScriptJson(
      exportModelJson(model, worldTitle: title),
    );
    final geoJson = _escapeScriptJson(exportGeoJson(model, worldTitle: title));

    final sunAzimuthDeg = model.environment.lighting.sunAzimuthDeg;
    final sunElevationDeg = model.environment.lighting.sunElevationDeg;

    return '''<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>$safeTitle — DaySeven 3D Viewer</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      background-color: #07090e;
      color: #e5e9f0;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
      overflow: hidden;
      width: 100vw;
      height: 100vh;
      user-select: none;
    }
    #gl-canvas {
      width: 100%;
      height: 100%;
      position: absolute;
      top: 0;
      left: 0;
      display: block;
      cursor: grab;
    }
    #gl-canvas:active {
      cursor: grabbing;
    }
    .hud {
      position: absolute;
      top: 16px;
      left: 16px;
      z-index: 10;
      background: rgba(18, 24, 32, 0.88);
      backdrop-filter: blur(8px);
      border: 1px solid rgba(255, 255, 255, 0.12);
      border-radius: 8px;
      padding: 16px 20px;
      max-width: 340px;
      box-shadow: 0 4px 20px rgba(0, 0, 0, 0.6);
      pointer-events: auto;
    }
    .hud h1 {
      font-size: 18px;
      font-weight: 600;
      margin-bottom: 6px;
      color: #eceff4;
    }
    .hud p {
      font-size: 12px;
      color: #8892b0;
      margin-bottom: 12px;
      line-height: 1.4;
    }
    .hud .stats {
      font-size: 12px;
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 6px 12px;
      margin-top: 8px;
      border-top: 1px solid rgba(255, 255, 255, 0.08);
      padding-top: 8px;
    }
    .hud .stat-item {
      display: flex;
      flex-direction: column;
    }
    .hud .stat-label {
      font-size: 10px;
      text-transform: uppercase;
      letter-spacing: 0.5px;
      color: #64748b;
    }
    .hud .stat-value {
      font-size: 13px;
      font-weight: 500;
      color: #e2e8f0;
    }
    #pin-overlay {
      position: absolute;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      pointer-events: none;
      z-index: 5;
    }
    .pin {
      position: absolute;
      transform: translate(-50%, -100%);
      display: flex;
      flex-direction: column;
      align-items: center;
      cursor: pointer;
      pointer-events: auto;
      transition: opacity 0.15s ease;
    }
    .pin-label {
      background: rgba(15, 23, 42, 0.9);
      border: 1px solid rgba(56, 189, 248, 0.4);
      border-radius: 4px;
      padding: 2px 6px;
      font-size: 10px;
      font-weight: 600;
      color: #38bdf8;
      white-space: nowrap;
      box-shadow: 0 2px 6px rgba(0,0,0,0.5);
    }
    .pin-icon {
      width: 14px;
      height: 14px;
      background: #38bdf8;
      clip-path: polygon(50% 100%, 0% 0%, 100% 0%);
      margin-top: -1px;
    }
    .landmark-tooltip {
      position: absolute;
      display: none;
      z-index: 20;
      background: rgba(15, 23, 42, 0.96);
      border: 1px solid #38bdf8;
      border-radius: 6px;
      padding: 8px 12px;
      font-size: 12px;
      color: #f8fafc;
      pointer-events: none;
      box-shadow: 0 4px 16px rgba(0, 0, 0, 0.7);
      transform: translate(-50%, -125%);
    }
    .landmark-tooltip .name {
      font-weight: 600;
      color: #38bdf8;
      margin-bottom: 2px;
    }
    .landmark-tooltip .coords {
      font-size: 10px;
      color: #94a3b8;
    }
  </style>
</head>
<body>
  <canvas id="gl-canvas"></canvas>
  <div id="pin-overlay"></div>

  <div class="hud">
    <h1>$safeTitle</h1>
    <p>Exported from DaySeven World Engine. Drag to orbit, scroll to zoom.</p>
    <div class="stats">
      <div class="stat-item">
        <span class="stat-label">Radius</span>
        <span class="stat-value">${model.geometry.radiusKm.toStringAsFixed(0)} km</span>
      </div>
      <div class="stat-item">
        <span class="stat-label">Axial Tilt</span>
        <span class="stat-value">${model.astronomy.axialTiltDeg.toStringAsFixed(1)}°</span>
      </div>
      <div class="stat-item">
        <span class="stat-label">Landmarks</span>
        <span class="stat-value">${model.landmarks.length}</span>
      </div>
      <div class="stat-item">
        <span class="stat-label">Atmosphere</span>
        <span class="stat-value">${model.environment.atmosphere.enabled ? "Active" : "None"}</span>
      </div>
    </div>
  </div>

  <div id="tooltip" class="landmark-tooltip">
    <div class="name" id="tt-name"></div>
    <div class="coords" id="tt-coords"></div>
  </div>

  <script id="world-metadata" type="application/json">
$metadataJson
  </script>
  <script id="world-geojson" type="application/json">
$geoJson
  </script>

  <script>
    (function() {
      const metadata = JSON.parse(document.getElementById('world-metadata').textContent);
      const canvas = document.getElementById('gl-canvas');
      const pinOverlay = document.getElementById('pin-overlay');
      const tooltip = document.getElementById('tooltip');
      const ttName = document.getElementById('tt-name');
      const ttCoords = document.getElementById('tt-coords');

      const gl = canvas.getContext('webgl', { antialias: true, alpha: false });
      if (!gl) {
        canvas.parentNode.textContent = 'WebGL not supported.';
        return;
      }

      // --- Build UV Sphere Mesh ---
      const lats = 48, lons = 72;
      const positions = [], normals = [], indices = [];

      for (let i = 0; i <= lats; i++) {
        const lat = -Math.PI / 2 + Math.PI * i / lats;
        const cosLat = Math.cos(lat);
        const y = Math.sin(lat);
        for (let j = 0; j <= lons; j++) {
          const lon = -Math.PI + 2 * Math.PI * j / lons;
          const x = cosLat * Math.sin(lon);
          const z = cosLat * Math.cos(lon);
          positions.push(x, y, z);
          normals.push(x, y, z);
        }
      }

      for (let i = 0; i < lats; i++) {
        for (let j = 0; j < lons; j++) {
          const first = i * (lons + 1) + j;
          const second = first + lons + 1;
          indices.push(first, second, first + 1);
          indices.push(second, second + 1, first + 1);
        }
      }

      const vsSource = `
        attribute vec3 aPosition;
        attribute vec3 aNormal;
        uniform mat4 uMatrix;
        uniform mat3 uNormalMatrix;
        varying vec3 vNormal;
        varying vec3 vPosition;
        void main() {
          vNormal = uNormalMatrix * aNormal;
          vPosition = aPosition;
          gl_Position = uMatrix * vec4(aPosition, 1.0);
        }
      `;

      const fsSource = `
        precision mediump float;
        varying vec3 vNormal;
        varying vec3 vPosition;
        uniform vec3 uLightDir;
        uniform vec3 uBaseColor;
        uniform vec3 uAtmoColor;
        uniform float uAtmoEnabled;

        void main() {
          vec3 n = normalize(vNormal);
          vec3 l = normalize(uLightDir);
          float diff = max(dot(n, l), 0.15);
          vec3 col = uBaseColor * diff;

          // Atmospheric rim
          if (uAtmoEnabled > 0.5) {
            float rim = 1.0 - max(dot(n, vec3(0.0, 0.0, 1.0)), 0.0);
            rim = pow(rim, 3.0) * 0.45;
            col += uAtmoColor * rim;
          }

          gl_FragColor = vec4(col, 1.0);
        }
      `;

      function createShader(gl, type, source) {
        const s = gl.createShader(type);
        gl.shaderSource(s, source);
        gl.compileShader(s);
        return s;
      }

      const program = gl.createProgram();
      gl.attachShader(program, createShader(gl, gl.VERTEX_SHADER, vsSource));
      gl.attachShader(program, createShader(gl, gl.FRAGMENT_SHADER, fsSource));
      gl.linkProgram(program);
      gl.useProgram(program);

      const posBuf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, posBuf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(positions), gl.STATIC_DRAW);

      const aPos = gl.getAttribLocation(program, 'aPosition');
      gl.enableVertexAttribArray(aPos);
      gl.vertexAttribPointer(aPos, 3, gl.FLOAT, false, 0, 0);

      const normBuf = gl.createBuffer();
      gl.bindBuffer(gl.ARRAY_BUFFER, normBuf);
      gl.bufferData(gl.ARRAY_BUFFER, new Float32Array(normals), gl.STATIC_DRAW);

      const aNorm = gl.getAttribLocation(program, 'aNormal');
      gl.enableVertexAttribArray(aNorm);
      gl.vertexAttribPointer(aNorm, 3, gl.FLOAT, false, 0, 0);

      const idxBuf = gl.createBuffer();
      gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, idxBuf);
      gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, new Uint16Array(indices), gl.STATIC_DRAW);

      const uMatrix = gl.getUniformLocation(program, 'uMatrix');
      const uNormalMatrix = gl.getUniformLocation(program, 'uNormalMatrix');
      const uLightDir = gl.getUniformLocation(program, 'uLightDir');
      const uBaseColor = gl.getUniformLocation(program, 'uBaseColor');
      const uAtmoColor = gl.getUniformLocation(program, 'uAtmoColor');
      const uAtmoEnabled = gl.getUniformLocation(program, 'uAtmoEnabled');

      gl.uniform3f(uBaseColor, 0.16, 0.24, 0.34);
      gl.uniform3f(uAtmoColor, 0.22, 0.74, 0.97);
      gl.uniform1f(uAtmoEnabled, metadata.environment && metadata.environment.atmosphere && metadata.environment.atmosphere.enabled ? 1.0 : 0.0);

      const sunAzRad = $sunAzimuthDeg * Math.PI / 180.0;
      const sunElRad = $sunElevationDeg * Math.PI / 180.0;
      gl.uniform3f(uLightDir, Math.cos(sunElRad) * Math.sin(sunAzRad), Math.sin(sunElRad), Math.cos(sunElRad) * Math.cos(sunAzRad));

      gl.enable(gl.DEPTH_TEST);
      gl.enable(gl.CULL_FACE);

      // --- Camera & Interaction ---
      let pitch = 0, yaw = 0, scale = 1.0;
      let isDragging = false, lastX = 0, lastY = 0;

      canvas.addEventListener('mousedown', e => {
        isDragging = true;
        lastX = e.clientX;
        lastY = e.clientY;
      });

      window.addEventListener('mouseup', () => isDragging = false);

      window.addEventListener('mousemove', e => {
        if (!isDragging) return;
        const dx = e.clientX - lastX;
        const dy = e.clientY - lastY;
        yaw += dx * 0.005;
        pitch = Math.max(-Math.PI / 2, Math.min(Math.PI / 2, pitch - dy * 0.005));
        lastX = e.clientX;
        lastY = e.clientY;
        render();
      });

      canvas.addEventListener('wheel', e => {
        e.preventDefault();
        scale = Math.max(0.5, Math.min(3.5, scale - e.deltaY * 0.001));
        render();
      }, { passive: false });

      // --- Landmark Pin Overlay ---
      const pins = [];
      if (metadata.landmarks && Array.isArray(metadata.landmarks)) {
        metadata.landmarks.forEach(lm => {
          const latRad = lm.latitude * Math.PI / 180.0;
          const lonRad = lm.longitude * Math.PI / 180.0;
          const cosLat = Math.cos(latRad);
          const x = cosLat * Math.sin(lonRad);
          const y = Math.sin(latRad);
          const z = cosLat * Math.cos(lonRad);

          const el = document.createElement('div');
          el.className = 'pin';
          const labelEl = document.createElement('div');
          labelEl.className = 'pin-label';
          labelEl.textContent = lm.name;
          const iconEl = document.createElement('div');
          iconEl.className = 'pin-icon';
          el.appendChild(labelEl);
          el.appendChild(iconEl);
          el.addEventListener('mouseenter', e => {
            ttName.textContent = lm.name;
            ttCoords.textContent = lm.latitude.toFixed(2) + '°, ' + lm.longitude.toFixed(2) + '°' + (lm.document ? ' • ' + lm.document : '');
            tooltip.style.left = e.clientX + 'px';
            tooltip.style.top = e.clientY + 'px';
            tooltip.style.display = 'block';
          });
          el.addEventListener('mouseleave', () => {
            tooltip.style.display = 'none';
          });
          pinOverlay.appendChild(el);
          pins.push({ lm, x, y, z, el });
        });
      }

      function rotate(x, y, z, pitch, yaw) {
        const cosP = Math.cos(pitch), sinP = Math.sin(pitch);
        const py = y * cosP - z * sinP;
        const pz = y * sinP + z * cosP;

        const cosY = Math.cos(yaw), sinY = Math.sin(yaw);
        return {
          x: x * cosY + pz * sinY,
          y: py,
          z: -x * sinY + pz * cosY
        };
      }

      function resize() {
        const w = window.innerWidth;
        const h = window.innerHeight;
        if (canvas.width !== w || canvas.height !== h) {
          canvas.width = w;
          canvas.height = h;
          gl.viewport(0, 0, w, h);
        }
      }

      function render() {
        resize();
        gl.clearColor(0.03, 0.04, 0.06, 1.0);
        gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

        const w = canvas.width, h = canvas.height;
        const aspect = w / h;
        const radius = Math.min(w, h) / 2 * 0.7 * scale;

        // Perspective / Orthographic projection
        const cosP = Math.cos(pitch), sinP = Math.sin(pitch);
        const cosY = Math.cos(yaw), sinY = Math.sin(yaw);

        // Rotation matrix (pitch and yaw)
        const rotMat = [
          cosY, 0, -sinY,
          sinP * sinY, cosP, sinP * cosY,
          cosP * sinY, -sinP, cosP * cosY
        ];

        // Combined MVP matrix
        const sX = (2 * radius) / w;
        const sY = (2 * radius) / h;
        const mvp = [
          rotMat[0] * sX, rotMat[3] * sY, rotMat[6] * 0.001, 0,
          rotMat[1] * sX, rotMat[4] * sY, rotMat[7] * 0.001, 0,
          rotMat[2] * sX, rotMat[5] * sY, rotMat[8] * 0.001, 0,
          0, 0, 0, 1
        ];

        gl.uniformMatrix4fv(uMatrix, false, new Float32Array(mvp));
        gl.uniformMatrix3fv(uNormalMatrix, false, new Float32Array(rotMat));

        gl.drawElements(gl.TRIANGLES, indices.length, gl.UNSIGNED_SHORT, 0);

        // Update Pins
        const cx = w / 2;
        const cy = h / 2;
        pins.forEach(pin => {
          const r = rotate(pin.x, pin.y, pin.z, pitch, yaw);
          if (r.z > 0.05) {
            const sx = cx + r.x * radius;
            const sy = cy - r.y * radius;
            pin.el.style.display = 'flex';
            pin.el.style.left = sx + 'px';
            pin.el.style.top = sy + 'px';
            pin.el.style.opacity = Math.min(1.0, r.z * 2.0);
          } else {
            pin.el.style.display = 'none';
          }
        });
      }

      window.addEventListener('resize', render);
      render();
    })();
  </script>
</body>
</html>
''';
  }

  /// Writes [model] JSON directly to [target].
  Future<void> exportModelJsonFile(
    DaySeven3DModel model,
    File target, {
    String? worldTitle,
  }) async {
    final content = exportModelJson(model, worldTitle: worldTitle);
    await target.writeAsString(content);
  }

  /// Writes [model] GeoJSON directly to [target].
  Future<void> exportGeoJsonFile(
    DaySeven3DModel model,
    File target, {
    String? worldTitle,
  }) async {
    final content = exportGeoJson(model, worldTitle: worldTitle);
    await target.writeAsString(content);
  }

  /// Writes [model] standalone WebGL 3D HTML directly to [target].
  Future<void> exportThreeJsHtmlFile(
    DaySeven3DModel model,
    File target, {
    String? worldTitle,
  }) async {
    final content = exportStandaloneThreeJsHtml(model, worldTitle: worldTitle);
    await target.writeAsString(content);
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _escapeScriptJson(String json) {
    return json.replaceAll('<', r'\u003c').replaceAll('>', r'\u003e');
  }
}
