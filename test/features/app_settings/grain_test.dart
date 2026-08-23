import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/app_settings/ui/grain.dart';

void main() {
  testWidgets('paints the surface and any grain behind content', (
    tester,
  ) async {
    const contentKey = Key('content');

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox(
          width: 100,
          height: 100,
          child: GrainOverlay(
            background: ColoredBox(color: Color(0xFFD9D9D9)),
            child: Text('Crisp', key: contentKey),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final stack = tester.widget<Stack>(find.byType(Stack));
    expect(stack.children.first, isA<Positioned>());
    expect(
      stack.children.take(stack.children.length - 1),
      everyElement(isA<Positioned>()),
    );
    expect(stack.children.last.key, contentKey);
  });
}
