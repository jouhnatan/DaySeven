import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/shared/platform/app_update.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:dayseven/shared/ui/update_dialog.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const release = AppRelease(
  platform: 'macos',
  version: AppVersion('1.4.0', 6),
  downloadUrl: 'https://example.test/DaySeven-macos.zip',
  installUrl: 'https://example.test/DaySeven.dmg',
  sha256: _sha,
  sizeBytes: 400,
  releaseNotes: 'Faster search.',
);

class StubReleases implements ReleaseDataSource {
  StubReleases([this.answer = release]);

  final AppRelease? answer;
  Object? error;

  @override
  Future<AppRelease?> currentRelease(String platform) async {
    if (error case final failure?) throw failure;
    return answer;
  }
}

/// Drives the dialog directly, so a state can be asserted on without waiting
/// for a real download to reach it.
class StubController extends AppUpdateController {
  StubController({StubReleases? releases, super.enabled = true})
    : super(releases ?? StubReleases(), Future.value(const AppVersion('1.3.0', 5)));

  void show(AppUpdateState next) => state = next;
}

/// The menu item's whole job: a button that calls runUpdateCheck, with a
/// ScaffoldMessenger above it for the two snackbar outcomes.
Future<void> pumpMenuAction(
  WidgetTester tester,
  StubController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appUpdateProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        theme: dsTheme(Brightness.dark),
        home: Scaffold(
          body: Consumer(
            builder: (context, ref, _) => TextButton(
              onPressed: () => runUpdateCheck(context, ref),
              child: const Text('Run updates'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Run updates'));
  await tester.pumpAndSettle();
}

Future<void> pumpDialog(
  WidgetTester tester,
  StubController controller, {
  bool mandatory = false,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appUpdateProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        theme: dsTheme(Brightness.dark),
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showUpdateDialog(
              context,
              release: release,
              mandatory: mandatory,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  tearDown(DsGlobalSettings.reset);

  testWidgets('names the version and shows the release notes', (tester) async {
    await pumpDialog(tester, StubController());

    expect(find.text('DaySeven 1.4.0 is available'), findsOneWidget);
    expect(find.text('Faster search.'), findsOneWidget);
    expect(find.text('Later'), findsOneWidget);
  });

  // Refusing to let someone close a dialog in an app they are trying to use
  // would be worse than running an old build, but it should not read as a
  // choice either.
  testWidgets('a mandatory update offers no Later', (tester) async {
    await pumpDialog(tester, StubController(), mandatory: true);

    expect(find.text('Later'), findsNothing);
    expect(find.textContaining('required'), findsOneWidget);
  });

  testWidgets('shows progress and locks the actions while downloading', (
    tester,
  ) async {
    final controller = StubController();
    await pumpDialog(tester, controller);

    controller.show(const DownloadingUpdate(release, 100));
    await tester.pump();

    expect(find.text('Downloading…'), findsOneWidget);
    // Nothing to press: closing mid-download would leave a half-written app.
    expect(find.text('Later'), findsNothing);
    expect(
      tester.widget<TextButton>(find.widgetWithText(TextButton, 'Downloading…')).onPressed,
      isNull,
    );

    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.25);
  });

  testWidgets('installing says the app will reopen itself', (tester) async {
    final controller = StubController();
    await pumpDialog(tester, controller);

    controller.show(const InstallingUpdate(release));
    await tester.pump();

    expect(find.textContaining('close and reopen'), findsOneWidget);
  });

  // Every failure path ends at the same offer, rather than at a dead end.
  testWidgets('a failure falls back to a manual download', (tester) async {
    final controller = StubController();
    await pumpDialog(tester, controller);

    controller.show(const UpdateFailed(release, 'The disk was full.'));
    await tester.pump();

    expect(find.text('The disk was full.'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  // The same offer on both platforms: the app installs it and reopens.
  testWidgets('offers to install in place', (tester) async {
    await pumpDialog(tester, StubController());

    expect(find.text('Update now'), findsOneWidget);
  });

  group('Run updates', () {
    testWidgets('offers the newer release', (tester) async {
      await pumpMenuAction(tester, StubController());

      expect(find.text('DaySeven 1.4.0 is available'), findsOneWidget);
    });

    testWidgets('says so when already current', (tester) async {
      // The feed's current release is the version this build already is.
      await pumpMenuAction(
        tester,
        StubController(
          releases: StubReleases(
            const AppRelease(
              platform: 'macos',
              version: AppVersion('1.3.0', 5),
              downloadUrl: 'https://example.test/DaySeven-macos.zip',
              sha256: _sha,
              sizeBytes: 400,
            ),
          ),
        ),
      );

      expect(find.text('DaySeven is up to date.'), findsOneWidget);
      expect(find.textContaining('is available'), findsNothing);
    });

    // Answering "up to date" to a question the app could not answer would be
    // a lie, so a failed check has to look different from a successful one.
    testWidgets('surfaces a failed check rather than claiming to be current', (
      tester,
    ) async {
      await pumpMenuAction(
        tester,
        StubController(releases: StubReleases()..error = Exception('offline')),
      );

      expect(find.textContaining('offline'), findsOneWidget);
      expect(find.text('DaySeven is up to date.'), findsNothing);
    });

    testWidgets('explains when there is no server to check against', (
      tester,
    ) async {
      await pumpMenuAction(tester, StubController(enabled: false));

      expect(find.textContaining('without a server'), findsOneWidget);
    });
  });
}
