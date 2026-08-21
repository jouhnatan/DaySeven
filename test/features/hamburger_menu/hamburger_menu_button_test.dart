import 'package:dayseven/features/hamburger_menu/ui/hamburger_menu_button.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens its supplied entries and invokes the selected action', (
    tester,
  ) async {
    var selected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: dsTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: HamburgerMenuButton(
              entries: [
                HamburgerMenuEntry(
                  label: 'Background grain…',
                  onSelected: () => selected = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.byTooltip('Menu'), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const Key('hamburger-menu-button'))),
      const Size.square(34),
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    expect(find.text('Background grain…'), findsOneWidget);

    await tester.tap(find.text('Background grain…'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
  });

  testWidgets('toggle entries expose a reusable checked state', (tester) async {
    var uncheckedSelected = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: dsTheme(Brightness.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topRight,
            child: HamburgerMenuButton(
              entries: [
                HamburgerMenuEntry.toggle(
                  label: 'Knowledge Base',
                  checked: true,
                  onSelected: () {},
                ),
                HamburgerMenuEntry.toggle(
                  label: 'Views',
                  checked: false,
                  onSelected: () => uncheckedSelected = true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const Key('hamburger-menu-toggle-check-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('hamburger-menu-toggle-check-1')),
      findsNothing,
    );
    expect(
      tester.getTopLeft(find.text('Knowledge Base')).dx,
      tester.getTopLeft(find.text('Views')).dx,
      reason: 'toggle labels share the normal left-aligned menu edge',
    );
    expect(
      tester
          .getCenter(find.byKey(const Key('hamburger-menu-toggle-check-0')))
          .dx,
      greaterThan(tester.getCenter(find.text('Knowledge Base')).dx),
      reason: 'the active checkmark is trailing, not leading',
    );

    await tester.tap(find.byKey(const Key('hamburger-menu-toggle-1')));
    await tester.pumpAndSettle();
    expect(uncheckedSelected, isTrue);
  });
}
