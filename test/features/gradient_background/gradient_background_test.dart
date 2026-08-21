import 'package:dayseven/features/gradient_background/ui/gradient_background.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _harness(Brightness brightness) => MaterialApp(
  theme: dsTheme(brightness),
  home: Scaffold(
    body: GradientBackground(isDark: brightness == Brightness.dark),
  ),
);

void main() {
  testWidgets('renders five layered radial pools in the light palette', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(Brightness.light));

    final base = tester.widget<ColoredBox>(
      find.byKey(const Key('gradient-background-base')),
    );
    final firstBlob = tester.widget<DecoratedBox>(
      find.byKey(const Key('gradient-background-blob-0')),
    );
    final gradient = (firstBlob.decoration as BoxDecoration).gradient;

    expect(base.color, const Color(0xFFF7FCF8));
    expect(gradient, isA<RadialGradient>());
    for (var index = 0; index < 5; index++) {
      expect(
        find.byKey(Key('gradient-background-blob-$index')),
        findsOneWidget,
      );
    }
    expect(
      gradientShellBackground(Brightness.light),
      kGradientShellBackgroundLight,
    );
  });

  testWidgets('uses the adaptive deep-green palette in dark mode', (
    tester,
  ) async {
    await tester.pumpWidget(_harness(Brightness.dark));

    final base = tester.widget<ColoredBox>(
      find.byKey(const Key('gradient-background-base')),
    );
    final firstBlob = tester.widget<DecoratedBox>(
      find.byKey(const Key('gradient-background-blob-0')),
    );
    final gradient = (firstBlob.decoration as BoxDecoration).gradient;

    expect(base.color, const Color(0xFF0A2117));
    expect(gradient, isA<RadialGradient>());
    expect(
      gradientShellBackground(Brightness.dark),
      kGradientShellBackgroundDark,
    );
  });
}
