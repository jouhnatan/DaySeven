import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/features/auth/ui/auth_button.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/test_fonts.dart';

Widget harness({List<Override> overrides = const []}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: dsTheme(Brightness.dark),
    home: const Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: Padding(padding: EdgeInsets.all(12), child: AuthButton()),
      ),
    ),
  ),
);

/// A signed-in session, as the app sees it after signing in.
User signedInUser({String username = 'haoyu', String? displayName}) => User(
  id: '466839ae-d51e-4e44-a8cb-a4d966f14918',
  appMetadata: const {},
  userMetadata: {'username': username, 'display_name': ?displayName},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026, 8, 19).toIso8601String(),
);

void main() {
  setUpAll(loadTestFonts);

  testWidgets('reads "Sign in" while signed out', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    expect(find.text('Sign in'), findsOneWidget);
  });

  testWidgets('is a rounded control', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    final container = tester.widget<AnimatedContainer>(
      find
          .ancestor(
            of: find.text('Sign in'),
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final decoration = container.decoration! as BoxDecoration;

    expect(decoration.borderRadius, const BorderRadius.all(DsRadius.control));
    expect(decoration.border, isNotNull);
    expect(decoration.color, DsColors.dark.island);
  });

  testWidgets('opens the sign-in dialog, asking for a username', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    // Signing in and creating an account are the same dialog.
    expect(find.text('Create an account'), findsOneWidget);
  });

  testWidgets('creating an account also asks for a display name', (
    tester,
  ) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Display name (optional)'), findsOneWidget);
  });

  group('once signed in', () {
    testWidgets('shows the display name instead of "Sign in"', (tester) async {
      await tester.pumpWidget(
        harness(
          overrides: [
            currentUserProvider.overrideWithValue(signedInUser()),
            myProfileProvider.overrideWith(
              (ref) async => const Profile(
                id: '466839ae-d51e-4e44-a8cb-a4d966f14918',
                username: 'haoyu',
                displayName: 'Haoyu',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Haoyu'), findsOneWidget);
      expect(find.text('Sign in'), findsNothing);
    });

    testWidgets('still shows as signed in when the profile cannot be read', (
      tester,
    ) async {
      // The failure that made this bug invisible: a live session, but the
      // profile row could not be fetched.
      await tester.pumpWidget(
        harness(
          overrides: [
            currentUserProvider.overrideWithValue(
              signedInUser(displayName: 'Haoyu'),
            ),
            myProfileProvider.overrideWith(
              (ref) async => throw const PostgrestException(
                message: 'column profiles.username does not exist',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Sign in'),
        findsNothing,
        reason: 'a failed profile fetch is not being signed out',
      );
      expect(
        find.text('Haoyu'),
        findsOneWidget,
        reason: 'the name falls back to the account metadata',
      );
    });

    testWidgets('falls back to the username when there is no display name', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(
          overrides: [
            currentUserProvider.overrideWithValue(signedInUser()),
            myProfileProvider.overrideWith((ref) async => null),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('haoyu'), findsOneWidget);
    });

    testWidgets('the menu offers the account actions', (tester) async {
      await tester.pumpWidget(
        harness(
          overrides: [
            currentUserProvider.overrideWithValue(signedInUser()),
            myProfileProvider.overrideWith(
              (ref) async => const Profile(
                id: '466839ae-d51e-4e44-a8cb-a4d966f14918',
                username: 'haoyu',
                displayName: 'Haoyu',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Haoyu'));
      await tester.pumpAndSettle();

      expect(find.text('@haoyu'), findsOneWidget);
      expect(find.text('Change display name…'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('a profile failure is offered for reading', (tester) async {
      await tester.pumpWidget(
        harness(
          overrides: [
            currentUserProvider.overrideWithValue(signedInUser()),
            myProfileProvider.overrideWith(
              (ref) async => throw const PostgrestException(
                message: 'permission denied for table profiles',
              ),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('haoyu'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Could not load your profile'));
      await tester.pumpAndSettle();

      expect(find.textContaining('permission denied'), findsOneWidget);
    });
  });

  testWidgets('looks the way it is meant to', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pump();

    await expectLater(
      find.byType(AuthButton),
      matchesGoldenFile('goldens/auth_button.png'),
    );
  });
}
