import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/shared/ui/dropdown_menu.dart';
import 'package:dayseven/shared/ui/theme.dart';

void main() {
  Widget app(Widget child) => MaterialApp(
        theme: dsTheme(),
        home: Scaffold(body: Center(child: child)),
      );

  group('DsDropdownMenuList data operations', () {
    test('starts empty and supports push and pop in LIFO order', () {
      final menu = DsDropdownMenuList<String>();
      expect(menu.isEmpty, isTrue);
      expect(menu.isNotEmpty, isFalse);
      expect(menu.length, 0);
      expect(menu.pop(), isNull);

      menu.pushItem(label: 'First', value: '1');
      menu.pushDivider();
      menu.pushHeader(text: 'Section');
      menu.pushItem(label: 'Second', value: '2');

      expect(menu.length, 4);
      expect(menu.isEmpty, isFalse);
      expect(menu.isNotEmpty, isTrue);

      final popped1 = menu.pop();
      expect(popped1, isA<DsDropdownMenuItem<String>>());
      expect((popped1! as DsDropdownMenuItem<String>).label, 'Second');
      expect(menu.length, 3);

      final popped2 = menu.pop();
      expect(popped2, isA<DsDropdownMenuHeader<String>>());
      expect((popped2! as DsDropdownMenuHeader<String>).text, 'Section');
      expect(menu.length, 2);

      final popped3 = menu.pop();
      expect(popped3, isA<DsDropdownMenuDivider<String>>());
      expect(menu.length, 1);

      final popped4 = menu.pop();
      expect(popped4, isA<DsDropdownMenuItem<String>>());
      expect((popped4! as DsDropdownMenuItem<String>).label, 'First');
      expect(menu.length, 0);
      expect(menu.pop(), isNull);
    });

    test('supports index access, insert, removeAt, and clear', () {
      final menu = DsDropdownMenuList<int>([
        const DsDropdownMenuItem(label: 'A', value: 1),
        const DsDropdownMenuItem(label: 'B', value: 2),
      ]);

      expect(menu.length, 2);
      expect((menu[0] as DsDropdownMenuItem<int>).label, 'A');
      expect((menu[1] as DsDropdownMenuItem<int>).label, 'B');

      menu.insert(1, const DsDropdownMenuDivider());
      expect(menu.length, 3);
      expect(menu[1], isA<DsDropdownMenuDivider<int>>());

      final removed = menu.removeAt(0);
      expect((removed as DsDropdownMenuItem<int>).label, 'A');
      expect(menu.length, 2);

      menu[0] = const DsDropdownMenuItem(label: 'Replaced', value: 99);
      expect((menu[0] as DsDropdownMenuItem<int>).label, 'Replaced');

      menu.clear();
      expect(menu.length, 0);
      expect(menu.isEmpty, isTrue);
    });
  });

  group('DsDropdownMenuList widget rendering and interactions', () {
    testWidgets('renders items, leading icons, and dividers', (tester) async {
      final menu = DsDropdownMenuList<String>();
      menu.pushItem(
        key: const Key('item-leading'),
        label: 'Open',
        value: 'open',
        icon: const Icon(Icons.folder, key: Key('folder-icon')),
        iconPosition: DsDropdownIconPosition.leading,
        shortcut: 'Cmd+O',
      );
      menu.pushDivider(key: const Key('menu-divider'));
      menu.pushItem(
        key: const Key('item-trailing'),
        label: 'Share',
        value: 'share',
        icon: const Icon(Icons.arrow_forward, key: Key('arrow-icon')),
        iconPosition: DsDropdownIconPosition.trailing,
      );

      String? selected;

      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                selected = await menu.show(context);
              },
              child: const Text('Show Menu'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Menu'));
      await tester.pumpAndSettle();

      // Check that menu items and elements appear
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Cmd+O'), findsOneWidget);
      expect(find.byKey(const Key('folder-icon')), findsOneWidget);
      expect(find.byKey(const Key('menu-divider')), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.byKey(const Key('arrow-icon')), findsOneWidget);

      // Verify leading icon position is left of the 'Open' text
      final folderIconRect = tester.getRect(find.byKey(const Key('folder-icon')));
      final openTextRect = tester.getRect(find.text('Open'));
      expect(folderIconRect.right, lessThan(openTextRect.left));

      // Verify trailing icon position is right of the 'Share' text
      final shareTextRect = tester.getRect(find.text('Share'));
      final arrowIconRect = tester.getRect(find.byKey(const Key('arrow-icon')));
      expect(shareTextRect.right, lessThan(arrowIconRect.left));

      // Tap an item and check returned value
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(selected, 'open');
    });

    testWidgets('renders checkmarks and header entries', (tester) async {
      final menu = DsDropdownMenuList<int>();
      menu.pushHeader(text: 'Settings Header');
      menu.pushItem(
        label: 'Toggle Option On',
        value: 1,
        isChecked: true,
      );
      menu.pushItem(
        label: 'Toggle Option Off',
        value: 2,
        isChecked: false,
      );

      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => menu.show(context),
              child: const Text('Show Menu'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Settings Header'), findsOneWidget);
      expect(find.text('Toggle Option On'), findsOneWidget);
      expect(find.text('Toggle Option Off'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);
    });

    testWidgets('destructive item and disabled item styles', (tester) async {
      final menu = DsDropdownMenuList<String>();
      menu.pushItem(
        label: 'Disabled Action',
        value: 'disabled',
        enabled: false,
      );
      menu.pushItem(
        label: 'Delete Action',
        value: 'delete',
        isDestructive: true,
      );

      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => menu.show(context),
              child: const Text('Show Menu'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Disabled Action'), findsOneWidget);
      expect(find.text('Delete Action'), findsOneWidget);
    });

    testWidgets('renders custom widgets, tooltips, and custom leading/trailing slots', (tester) async {
      final menu = DsDropdownMenuList<String>();
      menu.pushItem(
        label: 'Action with Tooltip',
        value: 'tooltip_val',
        tooltip: 'Helpful message',
        leading: const Icon(Icons.circle, key: Key('custom-leading-slot')),
        trailing: const Icon(Icons.star, key: Key('custom-trailing-slot')),
      );
      menu.pushCustom(
        const Text('Custom Embedded Row', key: Key('custom-embedded-row')),
      );

      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => menu.show(context),
              child: const Text('Show Menu'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Show Menu'));
      await tester.pumpAndSettle();

      expect(find.text('Action with Tooltip'), findsOneWidget);
      expect(find.byKey(const Key('custom-leading-slot')), findsOneWidget);
      expect(find.byKey(const Key('custom-trailing-slot')), findsOneWidget);
      expect(find.byKey(const Key('custom-embedded-row')), findsOneWidget);
      expect(
        tester.widget<Tooltip>(find.byType(Tooltip)).message,
        'Helpful message',
      );
    });
  });
}
