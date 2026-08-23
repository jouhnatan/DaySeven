/// The film grain the App settings design is built on.
///
/// The design produces its texture with an SVG `feTurbulence` filter the
/// browser evaluates live. Flutter has no equivalent, so the noise is baked
/// into two tiles by `scripts/generate_grain.dart` and repeated here.
///
/// The blend has to happen against what is already on the canvas, which rules
/// out `Image` and `DecorationImage` — both only composite with alpha, so a
/// multiply tile drawn that way just fogs the surface grey. Painting into the
/// same layer, on top of the child, is what lets `multiply` and `overlay` see
/// the pixels beneath them.
library;

import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// The two tiles, at the frequencies the design uses them.
enum GrainTile {
  /// The fine film over the whole composition.
  fine('assets/textures/grain_fine.png'),

  /// A coarser second pass, used only on the dark blocks so their flat fills
  /// breathe.
  coarse('assets/textures/grain_coarse.png');

  const GrainTile(this.asset);
  final String asset;
}

class GrainOverlay extends StatefulWidget {
  const GrainOverlay({
    super.key,
    required this.child,
    this.tile = GrainTile.fine,
    this.opacity = 0.42,
    this.blendMode = BlendMode.overlay,
    this.borderRadius,
  });

  final Widget child;
  final GrainTile tile;
  final double opacity;
  final BlendMode blendMode;

  /// Clips the grain to the surface it is grained onto, so it does not spill
  /// past a rounded corner.
  final BorderRadius? borderRadius;

  @override
  State<GrainOverlay> createState() => _GrainOverlayState();
}

class _GrainOverlayState extends State<GrainOverlay> {
  ui.Image? _tile;
  ImageStream? _stream;
  ImageStreamListener? _listener;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(GrainOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tile != widget.tile) _resolve();
  }

  void _resolve() {
    final provider = AssetImage(widget.tile.asset);
    final stream = provider.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;

    _detach();
    _listener = ImageStreamListener((image, _) {
      if (!mounted) return;
      setState(() => _tile = image.image);
    });
    _stream = stream..addListener(_listener!);
  }

  void _detach() {
    if (_stream != null && _listener != null) {
      _stream!.removeListener(_listener!);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tile = _tile;

    // Until the tile decodes there is simply no grain. One ungrained frame is
    // better than holding the dialog back on an asset load.
    if (tile == null) return widget.child;

    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: IgnorePointer(
            child: ClipRRect(
              borderRadius: widget.borderRadius ?? BorderRadius.zero,
              child: CustomPaint(
                painter: _GrainPainter(
                  tile: tile,
                  opacity: widget.opacity,
                  blendMode: widget.blendMode,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _GrainPainter extends CustomPainter {
  const _GrainPainter({
    required this.tile,
    required this.opacity,
    required this.blendMode,
  });

  final ui.Image tile;
  final double opacity;
  final BlendMode blendMode;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn straight onto the parent canvas. It is tempting to wrap this in a
    // saveLayer and fade the layer to get the strength down, but a saveLayer
    // starts out transparent, so the blend would have nothing beneath it to
    // blend with — the grain would composite over the surface instead of
    // multiplying into it, and wash every colour out.
    //
    // So strength is applied to the texture instead: each sample is pulled
    // toward the blend mode's identity — the value that leaves the surface
    // exactly as it was. Mid-grey for the symmetric modes this uses, white for
    // multiply, which only darkens and is not used here for that reason.
    final identity = blendMode == BlendMode.multiply ? 1.0 : 0.5;
    final offset = (1 - opacity) * identity * 255;

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..blendMode = blendMode
        // A tiling shader rather than a grid of drawImage calls: the tile is
        // seamless, so repeating it is the whole job.
        ..shader = ui.ImageShader(
          tile,
          TileMode.repeated,
          TileMode.repeated,
          Matrix4.identity().storage,
          // Nearest-neighbour. Grain is meant to be crisp, and on a
          // high-density display bilinear filtering smears each texel across
          // several device pixels, which turns the noise into soft directional
          // smudges rather than grain.
          filterQuality: FilterQuality.none,
        )
        ..colorFilter = ColorFilter.matrix(<double>[
          opacity, 0, 0, 0, offset,
          0, opacity, 0, 0, offset,
          0, 0, opacity, 0, offset,
          0, 0, 0, 1, 0,
        ]),
    );
  }

  @override
  bool shouldRepaint(_GrainPainter old) =>
      old.tile != tile ||
      old.opacity != opacity ||
      old.blendMode != blendMode;
}
