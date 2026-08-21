import 'package:dayseven/app/view.dart';
import 'package:dayseven/features/views/ui/views_menu.dart';
import 'package:dayseven/shared/ui/controls.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the Views header and switches workspace views', (
    tester,
  ) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(Brightness.dark),
          home: const Scaffold(
            body: SizedBox(width: 180, height: 400, child: ViewsMenu()),
          ),
        ),
      ),
    );

    final header = tester.widget<Text>(find.text('Views'));
    expect(header.style?.fontFamily, kUiHeaderFontFamily);
    expect(
      find.ancestor(of: find.text('Views'), matching: find.byType(DsIsland)),
      findsNothing,
      reason: 'the menu heading sits directly on the app background',
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Editor'), findsOneWidget);
    expect(container.read(viewProvider), DsView.home);

    await tester.tap(find.text('Editor'));
    await tester.pumpAndSettle();

    expect(container.read(viewProvider), DsView.editor);
  });
}
