import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/ui/error_box.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'test_fonts.dart';

Widget harness(Widget child) => MaterialApp(
  theme: dsTheme(Brightness.dark),
  home: Scaffold(
    body: Center(child: SizedBox(width: 320, child: child)),
  ),
);

void main() {
  setUpAll(loadTestFonts);

  testWidgets('looks the way it is meant to', (tester) async {
    await tester.pumpWidget(
      harness(
        const DsErrorBox(
          'Auth: Invalid login credentials · status 400 · code invalid_credentials',
        ),
      ),
    );

    await expectLater(
      find.byType(DsErrorBox),
      matchesGoldenFile('goldens/error_box.png'),
    );
  });

  testWidgets('an error can be selected, so it can be copied', (tester) async {
    await tester.pumpWidget(
      harness(const DsErrorBox('Invalid login credentials')),
    );

    final selectable = tester.widget<SelectableText>(
      find.byType(SelectableText),
    );
    expect(selectable.data, 'Invalid login credentials');

    // Selecting the text is what makes copying possible; a plain Text cannot.
    expect(find.byType(SelectableText), findsOneWidget);
  });

  testWidgets('the message sits on its own rounded panel', (tester) async {
    await tester.pumpWidget(harness(const DsErrorBox('Something went wrong')));

    final container = tester.widget<Container>(
      find
          .ancestor(
            of: find.byType(SelectableText),
            matching: find.byType(Container),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.borderRadius, const BorderRadius.all(DsRadius.control));
    expect(decoration.color, DsColors.dark.removal);
    expect(decoration.border, isNotNull);
  });

  group('what an error says', () {
    test('an auth failure carries its status and code', () {
      final described = describeError(
        const AuthApiException(
          'Invalid login credentials',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
      );

      expect(described, contains('Invalid login credentials'));
      expect(described, contains('400'));
      expect(described, contains('invalid_credentials'));
    });

    test('a database failure carries its code, details and hint', () {
      final described = describeError(
        const PostgrestException(
          message: 'duplicate key value violates unique constraint',
          code: '23505',
          details: 'Key (username) already exists.',
          hint: 'Choose another username.',
        ),
      );

      expect(described, contains('duplicate key'));
      expect(described, contains('23505'));
      expect(described, contains('already exists'));
      expect(described, contains('Choose another username.'));
    });

    test("our own messages are shown as written", () {
      expect(
        describeError(const SyncException('Sign in to propose a change.')),
        'Sign in to propose a change.',
      );
    });
  });
}
