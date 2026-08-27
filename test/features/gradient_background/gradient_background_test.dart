import 'package:dayseven/features/gradient_background/ui/gradient_background.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness() => MaterialApp(
  theme: dsTheme(),
  home: const Scaffold(body: GradientBackground()),
);

void main() {
  testWidgets('renders five layered radial pools on the application ground', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    final base = tester.widget<ColoredBox>(
      find.byKey(const Key('gradient-background-base')),
    );
    final firstBlob = tester.widget<DecoratedBox>(
      find.byKey(const Key('gradient-background-blob-0')),
    );
    final gradient = (firstBlob.decoration as BoxDecoration).gradient;

    expect(base.color, kGradientShellBackground);
    expect(gradient, isA<RadialGradient>());
    for (var index = 0; index < 5; index++) {
      expect(
        find.byKey(Key('gradient-background-blob-$index')),
        findsOneWidget,
      );
    }
    expect(gradientShellBackground(), kGradientShellBackground);
  });

  testWidgets('draws only in colours the rest of the interface already uses', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());

    // The gradient is a sanctioned exception to a system that otherwise has no
    // gradients at all. It earns that by introducing no new hue: every pool is
    // a palette colour, so the background can never drift away from the
    // surfaces standing on it.
    final palette = <Color>{
      CF.paper,
      CF.paperRaised,
      CF.inset,
      CF.bar,
      CF.hairline,
      CF.line,
      CF.sage,
      CF.fernWash,
      CF.warningWash,
    };

    expect(palette, contains(kGradientShellBackground));

    for (var index = 0; index < 5; index++) {
      final blob = tester.widget<DecoratedBox>(
        find.byKey(Key('gradient-background-blob-$index')),
      );
      final gradient =
          (blob.decoration as BoxDecoration).gradient! as RadialGradient;
      for (final color in gradient.colors) {
        expect(
          palette,
          contains(color.withValues(alpha: 1)),
          reason: 'blob $index introduced a colour outside the palette',
        );
      }
    }
  });
}
