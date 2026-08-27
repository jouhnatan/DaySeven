import 'dart:ui' show PointerDeviceKind;

import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/menu.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
    theme: dsTheme(),
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
    expect(buttonFill(tester), DsColors.cream.island);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(DsButton)));
    await tester.pumpAndSettle();

    expect(buttonFill(tester), DsColors.cream.selection);
  });

  testWidgets('a button can override the fill it takes while hovered', (
    tester,
  ) async {
    const custom = Color(0xFF123456);
    await tester.pumpWidget(
      app(
        DsButton(onPressed: () {}, highlight: custom, child: const Text('A')),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(find.byType(DsButton)));
    await tester.pumpAndSettle();

    expect(buttonFill(tester), custom);
  });

  testWidgets('a toggled-on button is a fern block, not a hover', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(DsButton(active: true, onPressed: () {}, child: const Text('A'))),
    );

    // Active is a state that persists. It is one of the two things fern is
    // spent on, so it fills solid rather than washing like a hover.
    expect(buttonFill(tester), DsColors.cream.fern);
  });

  testWidgets('list rows wash neutrally on hover', (tester) async {
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
    expect(decoration.color, DsColors.cream.hover);
    expect(decoration.borderRadius, const BorderRadius.all(DsRadius.row));
  });

  testWidgets('a selected row is a solid fern block with cream text', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(DsHoverRow(onTap: () {}, selected: true, child: const Text('Row'))),
    );

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(DsHoverRow),
        matching: find.byType(AnimatedContainer),
      ),
    );

    // Position is shown by fill, not by weight: the row the user is on is a
    // block of the accent, and its text is the cream that goes on it.
    expect(
      (container.decoration! as BoxDecoration).color,
      DsColors.cream.navSelected,
    );
    expect(
      tester.widget<DefaultTextStyle>(
        find
            .descendant(
              of: find.byType(DsHoverRow),
              matching: find.byType(DefaultTextStyle),
            )
            .last,
      ).style.color,
      DsColors.cream.onNavSelected,
    );
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
      DsColors.cream.hover,
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

  test('the palette clears its stated contrast ratios', () {
    double contrast(Color foreground, Color background) {
      final lighter =
          foreground.computeLuminance() > background.computeLuminance()
          ? foreground
          : background;
      final darker = identical(lighter, foreground) ? background : foreground;
      return (lighter.computeLuminance() + 0.05) /
          (darker.computeLuminance() + 0.05);
    }

    // The floor for anything a person has to read. `faint` is deliberately
    // absent: it measures about 3:1 and is legal only on disabled controls.
    for (final (name, foreground, background) in [
      ('ink on paper', CF.ink, CF.paper),
      ('ink on inset', CF.ink, CF.inset),
      ('ink on bar', CF.ink, CF.bar),
      ('muted on paper', CF.muted, CF.paper),
      ('muted on inset', CF.muted, CF.inset),
      ('muted on bar', CF.muted, CF.bar),
      ('onFern on fern', CF.onFern, CF.fern),
      ('onFern on fernHover', CF.onFern, CF.fernHover),
      ('slate on paper', CF.slate, CF.paper),
      ('success on paper', CF.success, CF.paper),
      ('warning on paper', CF.warning, CF.paper),
      ('danger on paper', CF.danger, CF.paper),
      ('onSage on sage', CF.onSage, CF.sage),
      ('ink on fernWash', CF.ink, CF.fernWash),
      ('ink on warningWash', CF.ink, CF.warningWash),
      ('ink on dangerWash', CF.ink, CF.dangerWash),
    ]) {
      expect(
        contrast(foreground, background),
        greaterThanOrEqualTo(4.5),
        reason: '$name is below AA',
      );
    }
  });

  test('a selected row keeps its text legible against the accent', () {
    // The two places fern is spent both put text on top of it, so the pair
    // that has to hold is onFern against fern rather than ink against a wash.
    expect(
      DsColors.cream.onNavSelected,
      isNot(equals(DsColors.cream.text)),
      reason: 'ink on a fern block is unreadable; it must invert to cream',
    );
  });
}
