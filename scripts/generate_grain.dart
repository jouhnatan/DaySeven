// Bakes the two noise tiles the App settings dialog is grained with.
//
// The design this comes from produces its grain with an SVG `feTurbulence`
// filter, which the browser evaluates live. Flutter has no equivalent, so the
// noise is generated once, here, and committed as an asset.
//
// Run from the repository root when the tiles need regenerating:
//
//   dart run scripts/generate_grain.dart
//
// The seed is fixed, so re-running produces byte-identical files.
//
// The PNG is written by hand rather than through a package: an 8-bit greyscale
// image is a header, one zlib stream and a footer, `dart:io` already has the
// zlib, and this way the repository gains no dependency for a file that is
// generated once and then just sits there.
// A command-line script: stdout is how it reports, not a stray debug print.
// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

void main() {
  _write('assets/textures/grain_fine.png', size: 180, octaves: 4, lattice: 90);
  _write(
    'assets/textures/grain_coarse.png',
    size: 120,
    octaves: 3,
    lattice: 40,
    // Coarser and stronger: this one only has to keep a flat dark fill from
    // looking like printed plastic, and dark surfaces swallow texture.
    depth: 190,
  );
}

void _write(
  String path, {
  required int size,
  required int octaves,
  required int lattice,
  int depth = 150,
}) {
  final field = _fractalNoise(
    size: size,
    octaves: octaves,
    lattice: lattice,
    seed: 20260822,
  );

  // One filter byte (0 = none) in front of each row, which is what the PNG
  // scanline format expects.
  //
  // The noise is centred on mid-grey and given a small amplitude, rather than
  // spanning the range. These tiles are blended with a mode whose identity is
  // 128 — a sample above it lightens, one below it darkens, and the average
  // leaves the surface exactly the colour it was. That is what lets the dialog
  // be grained and still be the palette's colours. Noise hanging off white can
  // only darken, and drags every surface off its specified value.
  final raw = Uint8List(size * (size + 1));
  var at = 0;
  for (var y = 0; y < size; y++) {
    raw[at++] = 0;
    for (var x = 0; x < size; x++) {
      final shade = 128 + (field[y * size + x] - 0.5) * depth;
      raw[at++] = shade.round().clamp(0, 255);
    }
  }

  final png = BytesBuilder()
    ..add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  final ihdr = BytesBuilder()
    ..add(_uint32(size))
    ..add(_uint32(size))
    ..add(const [
      8, // bit depth
      0, // colour type 0: greyscale. Opacity is the widget's decision.
      0, // deflate
      0, // adaptive filtering
      0, // no interlace
    ]);
  png.add(_chunk('IHDR', ihdr.takeBytes()));
  png.add(_chunk('IDAT', ZLibCodec(level: 9).encode(raw)));
  png.add(_chunk('IEND', const []));

  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(png.takeBytes());
  print('wrote $path — ${size}x$size, $octaves octaves');
}

List<int> _uint32(int value) =>
    [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];

List<int> _chunk(String type, List<int> data) {
  final body = <int>[...ascii.encode(type), ...data];
  return [..._uint32(data.length), ...body, ..._uint32(_crc32(body))];
}

int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : crc >> 1;
    }
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

/// Per-pixel noise with a little low-frequency clumping, in [0,1].
///
/// Mostly white noise, deliberately. Interpolated lattice noise on its own is
/// separable along x and y, and that separability shows up as faint horizontal
/// and vertical streaks — very visible once the tile is magnified on a
/// high-density display, and not at all what grain looks like. Film grain is
/// close to per-pixel random; the smooth octaves are only here to stop it
/// looking like uniform television static, so they are kept quiet.
Float32List _fractalNoise({
  required int size,
  required int octaves,
  required int lattice,
  required int seed,
}) {
  final out = Float32List(size * size);
  final white = Random(seed * 31 + 7);

  // The dominant term. Uncorrelated between neighbouring pixels, so it carries
  // no direction for the eye to find a line in.
  const whiteWeight = 0.72;
  for (var i = 0; i < out.length; i++) {
    out[i] = whiteWeight * white.nextDouble();
  }

  var amplitude = (1 - whiteWeight) / 2;
  var total = whiteWeight;
  var cells = lattice;

  for (var octave = 0; octave < octaves; octave++) {
    // Every octave's lattice must divide the tile, or a seam reappears where
    // the texture repeats.
    final period = _largestDivisorAtMost(size, cells);
    final grid = _lattice(period, seed + octave);

    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        out[y * size + x] += amplitude * _sample(grid, period, size, x, y);
      }
    }

    total += amplitude;
    amplitude *= 0.5;
    cells = max(2, cells ~/ 2);
  }

  for (var i = 0; i < out.length; i++) {
    out[i] = (out[i] / total).clamp(0.0, 1.0);
  }
  return out;
}

int _largestDivisorAtMost(int size, int cap) {
  for (var d = min(cap, size); d >= 2; d--) {
    if (size % d == 0) return d;
  }
  return 2;
}

Float32List _lattice(int period, int seed) {
  final random = Random(seed);
  final grid = Float32List(period * period);
  for (var i = 0; i < grid.length; i++) {
    grid[i] = random.nextDouble();
  }
  return grid;
}

/// Bilinear sample with wrapping, so opposite edges of the tile agree.
double _sample(Float32List grid, int period, int size, int x, int y) {
  final scale = period / size;
  final fx = x * scale;
  final fy = y * scale;
  final x0 = fx.floor();
  final y0 = fy.floor();
  final tx = _smooth(fx - x0);
  final ty = _smooth(fy - y0);

  double at(int gx, int gy) => grid[(gy % period) * period + (gx % period)];

  final top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * tx;
  final bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * tx;
  return top + (bottom - top) * ty;
}

/// Smoothstep, so the lattice does not show as a grid of creases.
double _smooth(double t) => t * t * (3 - 2 * t);
