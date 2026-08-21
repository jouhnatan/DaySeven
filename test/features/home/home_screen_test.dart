import 'package:dayseven/features/home/ui/home_screen.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../support/test_fonts.dart';

class _FakeAuthRepository extends AuthRepository {
  bool signedOut = false;

  @override
  Future<void> signOut() async {
    signedOut = true;
  }
}

User _signedInUser() => User(
  id: '466839ae-d51e-4e44-a8cb-a4d966f14918',
  appMetadata: const {},
  userMetadata: const {'username': 'haoyu', 'display_name': 'Haoyu Metadata'},
  aud: 'authenticated',
  createdAt: DateTime.utc(2026, 8, 19).toIso8601String(),
);

Widget _harness({
  Brightness brightness = Brightness.light,
  List<Override> overrides = const [],
}) => ProviderScope(
  overrides: overrides,
  child: MaterialApp(
    theme: dsTheme(brightness),
    home: const Scaffold(body: HomeScreen()),
  ),
);

void main() {
  setUpAll(loadTestFonts);

  testWidgets('uses a centered Geist greeting and both cards', (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    final greeting = tester.widget<Text>(find.text('Ready to build, Guest?'));

    expect(greeting.textAlign, TextAlign.center);
    expect(greeting.style?.fontFamily, kUiHeaderFontFamily);
    expect(find.text('Recent Files'), findsOneWidget);
    expect(find.text('User Settings'), findsOneWidget);
  });

  testWidgets('cards are equal columns when wide', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump();

    final recent = tester.getRect(
      find.byKey(const Key('home-recent-files-card')),
    );
    final settings = tester.getRect(
      find.byKey(const Key('home-user-settings-card')),
    );

    expect(recent.top, settings.top);
    expect(recent.width, settings.width);
    expect(recent.height, settings.height);
    expect(recent.right, lessThan(settings.left));
  });

  testWidgets('cards stack when the view is narrower than 720 pixels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_harness());
    await tester.pump();

    final recent = tester.getRect(
      find.byKey(const Key('home-recent-files-card')),
    );
    final settings = tester.getRect(
      find.byKey(const Key('home-user-settings-card')),
    );

    expect(settings.top, greaterThan(recent.bottom));
    expect(settings.left, recent.left);
    expect(settings.width, recent.width);
  });

  testWidgets('signed-out settings show status and the existing sign-in flow', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);

    await tester.tap(find.byKey(const Key('home-sign-in')));
    await tester.pumpAndSettle();

    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
  });

  testWidgets('signed-in settings show a read-only display name and log out', (
    tester,
  ) async {
    final auth = _FakeAuthRepository();
    await tester.pumpWidget(
      _harness(
        overrides: [
          currentUserProvider.overrideWithValue(_signedInUser()),
          myProfileProvider.overrideWith(
            (ref) async => const Profile(
              id: '466839ae-d51e-4e44-a8cb-a4d966f14918',
              username: 'haoyu',
              displayName: 'Haoyu',
            ),
          ),
          authRepositoryProvider.overrideWithValue(auth),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ready to build, Haoyu?'), findsOneWidget);
    expect(find.text('Display name'), findsOneWidget);
    expect(find.byKey(const Key('home-display-name')), findsOneWidget);
    expect(find.text('Haoyu'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);

    await tester.tap(find.byKey(const Key('home-log-out')));
    await tester.pumpAndSettle();

    expect(auth.signedOut, isTrue);
  });
}
