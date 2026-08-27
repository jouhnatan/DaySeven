/// The optional full-window radial background used by the Home experience.
///
/// This is a deliberate, documented departure from the design system, which
/// otherwise forbids gradients. It is kept quiet so that it reads as
/// atmosphere rather than as a coloured hero: the ground is the same recessed
/// cream the rest of the application stands on, the washes are drawn only from
/// the palette's decorative colours, and nothing on top of it changes.
///
/// It is light, like everything else here. There is no dark variant.
library;

import 'package:flutter/material.dart';

import 'package:dayseven/shared/ui/theme.dart';

/// The window colour behind the gradient. It matches the ordinary application
/// ground, so islands separate from it the same way in either mode and the
/// native title bar is handed one colour.
const kGradientShellBackground = CF.inset;

Color gradientShellBackground() => kGradientShellBackground;

class GradientBackground extends StatelessWidget {
  const GradientBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final unit = constraints.biggest.shortestSide;
        // Decorative palette colours only: sage for the fern note, and the
        // warm creams for everything else. No hue enters here that is not
        // already somewhere else in the interface.
        const colors = [
          CF.sage,
          CF.warningWash,
          CF.fernWash,
          CF.sage,
          CF.bar,
        ];

        return ColoredBox(
          key: const Key('gradient-background-base'),
          color: kGradientShellBackground,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned(
                left: -unit * 0.24,
                top: -unit * 0.20,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-0'),
                  size: unit * 0.78,
                  color: colors[0],
                  opacity: 0.55,
                ),
              ),
              Positioned(
                right: -unit * 0.18,
                top: height * 0.02,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-1'),
                  size: unit * 0.68,
                  color: colors[1],
                  opacity: 0.42,
                ),
              ),
              Positioned(
                left: width * 0.30,
                top: height * 0.24,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-2'),
                  size: unit * 0.50,
                  color: colors[2],
                  opacity: 0.38,
                ),
              ),
              Positioned(
                left: -unit * 0.18,
                bottom: -unit * 0.24,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-3'),
                  size: unit * 0.72,
                  color: colors[3],
                  opacity: 0.50,
                ),
              ),
              Positioned(
                right: -unit * 0.06,
                bottom: -unit * 0.30,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-4'),
                  size: unit * 0.82,
                  color: colors[4],
                  opacity: 0.40,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _GradientBlob extends StatelessWidget {
  const _GradientBlob({
    required this.blobKey,
    required this.size,
    required this.color,
    required this.opacity,
  });

  final Key blobKey;
  final double size;
  final Color color;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        key: blobKey,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            colors: [
              color.withValues(alpha: opacity),
              color.withValues(alpha: opacity * 0.48),
              color.withValues(alpha: 0),
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
      ),
    );
  }
}
