import 'dart:ui' show PointerDeviceKind;

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: dsTheme(Brightness.light),
    home: Scaffold(body: Center(child: child)),
  );

  Color buttonFill(WidgetTester tester) {
    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DsButton),
        matching: find.byType(AnimatedContainer),
      ),
    );
    return (container.decoration! as BoxDecoration).color!;
  }

  testWidgets('actionable buttons use the theme highlight when hovered', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(DsButton(onPressed: () {}, child: const Text('A'))),
    );
    expect(buttonFill(tester), DsColors.light.island);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(DsButton)));
    await tester.pumpAndSettle();

    expect(buttonFill(tester), DsColors.light.buttonHighlight);
  });

  testWidgets('a button can override its highlight', (tester) async {
    const custom = Color(0xFF123456);
    await tester.pumpWidget(
      app(DsButton(active: true, highlight: custom, child: const Text('A'))),
    );

    expect(buttonFill(tester), custom);
  });

  testWidgets('list rows use the green highlight and rounder shape', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(DsHoverRow(onTap: () {}, child: const Text('Row'))),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(DsHoverRow)));
    await tester.pumpAndSettle();

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DsHoverRow),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, DsColors.light.buttonHighlight);
    expect(decoration.borderRadius, const BorderRadius.all(DsRadius.menuItem));
  });

  testWidgets('popup items inset their rounded green highlight', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => DsButton(
            onPressed: () => showDsMenu<int>(
              context: context,
              items: const [
                DsMenuItem<int>(value: 1, child: Text('Menu item')),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final menuItem = find.byType(DsMenuItem<int>);
    final ink = tester.widget<InkWell>(
      find.descendant(of: menuItem, matching: find.byType(InkWell)),
    );
    expect(
      ink.overlayColor!.resolve(const {WidgetState.hovered}),
      DsColors.light.buttonHighlight,
    );
    expect(ink.borderRadius, const BorderRadius.all(DsRadius.menuItem));
    expect(
      find.descendant(
        of: menuItem,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Padding &&
              widget.padding ==
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('menu dividers leave equal space around adjacent items', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => DsButton(
            onPressed: () => showDsMenu<int>(
              context: context,
              items: const [
                DsMenuItem<int>(value: 1, child: Text('Before')),
                DsMenuDivider(),
                DsMenuItem<int>(value: 2, child: Text('After')),
              ],
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    Finder highlightFor(String label) {
      final item = find.ancestor(
        of: find.text(label),
        matching: find.byType(DsMenuItem<int>),
      );
      return find.descendant(of: item, matching: find.byType(InkWell));
    }

    final beforeHighlight = highlightFor('Before');
    final afterHighlight = highlightFor('After');
    final line = find.byType(Divider);
    final lineTop = tester.getTopLeft(line).dy;
    final lineBottom = tester.getBottomLeft(line).dy;
    final spaceAbove = lineTop - tester.getBottomLeft(beforeHighlight).dy;
    final spaceBelow = tester.getTopLeft(afterHighlight).dy - lineBottom;

    expect(spaceAbove, kDsMenuDividerSpacing + 3);
    expect(spaceBelow, kDsMenuDividerSpacing + 3);
    expect(spaceAbove, spaceBelow);
  });

  test('button highlights keep text legible in both themes', () {
    double contrast(Color foreground, Color background) {
      final lighter =
          foreground.computeLuminance() > background.computeLuminance()
          ? foreground
          : background;
      final darker = identical(lighter, foreground) ? background : foreground;
      return (lighter.computeLuminance() + 0.05) /
          (darker.computeLuminance() + 0.05);
    }

    expect(
      contrast(DsColors.dark.text, DsColors.dark.buttonHighlight),
      greaterThanOrEqualTo(4.5),
    );
    expect(
      contrast(DsColors.light.text, DsColors.light.buttonHighlight),
      greaterThanOrEqualTo(4.5),
    );
  });
}
