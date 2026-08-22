import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/features/editor/ui/editor_screen.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('reviewer document surface is pointer-read-only', (tester) async {
    const document = BlockDocument(
      id: 'doc-1',
      title: 'Aldenmoor',
      blocks: [
        ParagraphBlock(
          id: 'p-1',
          spans: [TextSpanNode(text: 'Canonical words')],
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: dsTheme(Brightness.dark),
          home: const Scaffold(
            body: DocumentEditor(
              open: OpenDocument(
                relativePath: 'Aldenmoor.md',
                document: document,
                dirty: false,
              ),
              readOnly: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final blockers = tester
        .widgetList<AbsorbPointer>(find.byType(AbsorbPointer))
        .where((widget) => widget.absorbing);
    expect(blockers.length, greaterThanOrEqualTo(3));
    expect(find.text('Canonical words'), findsOneWidget);
  });
}
