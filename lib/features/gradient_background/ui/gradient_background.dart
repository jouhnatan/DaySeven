/// The optional full-window radial background used by the Home experience.
library;

import 'package:flutter/material.dart';

const kGradientShellBackgroundLight = Color(0xFFDCEFE2);
const kGradientShellBackgroundDark = Color(0xFF081A11);

Color gradientShellBackground(Brightness brightness) =>
    brightness == Brightness.dark
    ? kGradientShellBackgroundDark
    : kGradientShellBackgroundLight;

class GradientBackground extends StatelessWidget {
  const GradientBackground({required this.isDark, super.key});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final unit = constraints.biggest.shortestSide;
        final colors = isDark
            ? const [
                Color(0xFF188A57),
                Color(0xFF6F942D),
                Color(0xFF087A6B),
                Color(0xFF145B38),
                Color(0xFF39A86D),
              ]
            : const [
                Color(0xFF78DFA5),
                Color(0xFFCBEA72),
                Color(0xFF54CEB0),
                Color(0xFFB2F0C6),
                Color(0xFF38BE7A),
              ];

        return ColoredBox(
          key: const Key('gradient-background-base'),
          color: isDark ? const Color(0xFF0A2117) : const Color(0xFFF7FCF8),
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
                  opacity: isDark ? 0.72 : 0.82,
                ),
              ),
              Positioned(
                right: -unit * 0.18,
                top: height * 0.02,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-1'),
                  size: unit * 0.68,
                  color: colors[1],
                  opacity: isDark ? 0.56 : 0.76,
                ),
              ),
              Positioned(
                left: width * 0.30,
                top: height * 0.24,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-2'),
                  size: unit * 0.50,
                  color: colors[2],
                  opacity: isDark ? 0.54 : 0.66,
                ),
              ),
              Positioned(
                left: -unit * 0.18,
                bottom: -unit * 0.24,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-3'),
                  size: unit * 0.72,
                  color: colors[3],
                  opacity: isDark ? 0.70 : 0.82,
                ),
              ),
              Positioned(
                right: -unit * 0.06,
                bottom: -unit * 0.30,
                child: _GradientBlob(
                  blobKey: const Key('gradient-background-blob-4'),
                  size: unit * 0.82,
                  color: colors[4],
                  opacity: isDark ? 0.54 : 0.62,
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
