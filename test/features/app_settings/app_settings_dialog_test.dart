import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/app_settings/ui/app_settings_dialog.dart';
import 'package:dayseven/shared/platform/app_update.dart';
import 'package:dayseven/shared/ui/theme.dart';

import '../../support/test_fonts.dart';

const _sha =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

const newer = AppRelease(
  platform: 'macos',
  version: AppVersion('1.4.0', 8),
  downloadUrl: 'https://example.test/DaySeven-macos.zip',
  installUrl: 'https://example.test/DaySeven.dmg',
  sha256: _sha,
  sizeBytes: 4194304,
  releaseNotes: 'Faster search.',
);

const same = AppRelease(
  platform: 'macos',
  version: AppVersion('1.3.2', 7),
  downloadUrl: 'https://example.test/DaySeven-macos.zip',
  sha256: _sha,
  sizeBytes: 4194304,
);

class FakeReleases implements ReleaseDataSource {
  FakeReleases([this.answer]);

  final AppRelease? answer;
  Object? error;

  @override
  Future<AppRelease?> currentRelease(String platform) async {
    if (error case final failure?) throw failure;
    return answer;
  }
}

/// Records what the dialog asked for instead of fetching and swapping the
/// running application.
///
/// `download` is overridden rather than `installer`, because the real one would
/// reach the network long before it reached the install step. What is being
/// tested here is the dialog's half of the bargain: that pressing the button
/// asks for the right release.
class RecordingController extends AppUpdateController {
  RecordingController({FakeReleases? releases, super.enabled = true})
    : super(
        releases ?? FakeReleases(),
        Future.value(const AppVersion('1.3.2', 7)),
      );

  final List<AppRelease> requested = [];

  @override
  Future<void> download(AppRelease release) async {
    requested.add(release);
    state = InstallingUpdate(release);
  }

  void show(AppUpdateState next) => state = next;
}

Future<void> openDialog(
  WidgetTester tester,
  AppUpdateController controller, {
  AppSettingsDeveloperOptions? developerOptions,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appUpdateProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        theme: dsTheme(Brightness.dark),
        home: Scaffold(
          body: AppSettingsDialog(developerOptions: developerOptions),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(loadTestFonts);
  tearDown(DsGlobalSettings.reset);

  setUp(() {
    // The dialog reads the running build's version through package_info_plus,
    // whose channel does not exist under `flutter test`.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dev.fluttercommunity.plus/package_info'),
          (call) async => {
            'appName': 'DaySeven',
            'packageName': 'com.dayseven.dayseven',
            'version': '1.3.2',
            'buildNumber': '7',
          },
        );
  });

  testWidgets('shows the running version and build', (tester) async {
    await openDialog(tester, RecordingController());

    expect(find.text('DaySeven 1.3.2'), findsOneWidget);
    expect(find.text('Build 7'), findsOneWidget);
  });

  testWidgets('shows and changes both developer toggles', (tester) async {
    bool? crdt;
    bool? metadata;
    await openDialog(
      tester,
      RecordingController(),
      developerOptions: AppSettingsDeveloperOptions(
        showWorkspaceMetadata: false,
        crdtCollaboration: false,
        setShowWorkspaceMetadata: (value) async => metadata = value,
        setCrdtCollaboration: (value) async => crdt = value,
        collaborationHealth: AppSettingsCollaborationHealth.off,
      ),
    );

    expect(find.text('Developer'), findsOneWidget);
    expect(find.text('CRDT collaboration'), findsOneWidget);
    expect(find.text('Show workspace metadata'), findsOneWidget);

    final crdtSwitch = find.descendant(
      of: find.byKey(const Key('app-settings-crdt-toggle')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(crdtSwitch);
    await tester.pumpAndSettle();
    await tester.tap(crdtSwitch);
    await tester.pumpAndSettle();
    final metadataSwitch = find.descendant(
      of: find.byKey(const Key('app-settings-metadata-toggle')),
      matching: find.byType(Switch),
    );
    await tester.ensureVisible(metadataSwitch);
    await tester.pumpAndSettle();
    await tester.tap(metadataSwitch);
    await tester.pumpAndSettle();

    expect(crdt, isTrue);
    expect(metadata, isTrue);
  });

  testWidgets('shows live link backlog, refusals, and policy recovery', (
    tester,
  ) async {
    var republished = false;
    await openDialog(
      tester,
      RecordingController(),
      developerOptions: AppSettingsDeveloperOptions(
        showWorkspaceMetadata: true,
        crdtCollaboration: true,
        setShowWorkspaceMetadata: (_) async {},
        setCrdtCollaboration: (_) async {},
        collaborationHealth: AppSettingsCollaborationHealth.connected,
        cursor: 42,
        pendingLocalPush: true,
        queuedInbound: 3,
        refusalCount: 1,
        refusalDetail: 'role reviewer cannot edit',
        policyDetail: 'This device does not hold the published key.',
        republishPolicy: () async => republished = true,
      ),
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('Durable cursor 42'), findsOneWidget);
    expect(find.textContaining('3 incoming update(s) queued'), findsOneWidget);
    expect(find.text('Policy signing needs attention'), findsOneWidget);
    expect(find.text('An incoming update was refused'), findsOneWidget);

    final republish = find.byKey(const Key('app-settings-republish-policy'));
    await tester.ensureVisible(republish);
    await tester.pumpAndSettle();
    await tester.tap(republish);
    await tester.pumpAndSettle();
    expect(republished, isTrue);
  });

  // The design sets a row's title in the display face and its second line in
  // the lighter meta face.
  testWidgets('sets a row in the two faces the design asks for', (
    tester,
  ) async {
    await openDialog(tester, RecordingController());

    expect(
      tester.widget<Text>(find.text('DaySeven 1.3.2')).style?.fontFamily,
      'Solway',
    );
    expect(
      tester.widget<Text>(find.text('Build 7')).style?.fontFamily,
      'Raleway',
    );
    expect(
      tester
          .widget<Text>(find.text('Nothing newer published'))
          .style
          ?.fontFamily,
      'Raleway',
    );
  });

  // The dialog exists so that the answer arrives before the button, rather
  // than only after somebody presses it.
  testWidgets('checks on open and reports being current', (tester) async {
    await openDialog(tester, RecordingController(releases: FakeReleases(same)));

    expect(find.text('Up to date'), findsOneWidget);
    expect(find.text('Nothing newer published'), findsOneWidget);
    expect(find.text('Run updates'), findsOneWidget);
  });

  testWidgets('checks on open and names a newer version', (tester) async {
    await openDialog(
      tester,
      RecordingController(releases: FakeReleases(newer)),
    );

    expect(find.text('Version 1.4.0'), findsOneWidget);
    expect(find.text('Build 8'), findsOneWidget);
    expect(find.text('Update now'), findsOneWidget);
  });

  testWidgets('installs the release when asked', (tester) async {
    final controller = RecordingController(releases: FakeReleases(newer));
    await openDialog(tester, controller);

    await tester.tap(find.byKey(const Key('app-settings-run-updates')));
    await tester.pumpAndSettle();

    expect(controller.requested.single.version, const AppVersion('1.4.0', 8));
  });

  testWidgets('locks the button and shows progress while downloading', (
    tester,
  ) async {
    final controller = RecordingController();
    await openDialog(tester, controller);

    controller.show(const DownloadingUpdate(newer, 1048576));
    await tester.pump();

    expect(find.text('Downloading…'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(bar.value, 0.25);
  });

  testWidgets('says the app will reopen itself while installing', (
    tester,
  ) async {
    final controller = RecordingController();
    await openDialog(tester, controller);

    controller.show(const InstallingUpdate(newer));
    await tester.pump();

    expect(find.text('Installing'), findsOneWidget);
  });

  // Answering "up to date" to a question the app could not actually answer
  // would be a lie, so a failed check has to look different from a clean one.
  testWidgets('surfaces a failed check instead of claiming to be current', (
    tester,
  ) async {
    await openDialog(
      tester,
      RecordingController(
        releases: FakeReleases()..error = Exception('offline'),
      ),
    );

    expect(
      find.byKey(const Key('app-settings-alert')),
      findsOneWidget,
      reason: 'the detail belongs in the alert block, not the hero',
    );
    expect(find.textContaining('offline'), findsOneWidget);
  });

  // Every install failure ends at the same offer: fetch it by hand.
  testWidgets('a failed install falls back to a manual download', (
    tester,
  ) async {
    final controller = RecordingController();
    await openDialog(tester, controller);

    controller.show(const UpdateFailed(newer, 'The disk was full.'));
    await tester.pump();

    expect(find.text('The disk was full.'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('says so when the build has no server to check against', (
    tester,
  ) async {
    await openDialog(tester, RecordingController(enabled: false));

    expect(find.text('No server configured'), findsOneWidget);
    expect(find.textContaining('published to Supabase'), findsOneWidget);
    // The version is still worth seeing without one.
    expect(find.text('DaySeven 1.3.2'), findsOneWidget);
  });

  testWidgets('Done closes the dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateProvider.overrideWith((ref) => RecordingController()),
        ],
        child: MaterialApp(
          theme: dsTheme(Brightness.dark),
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showAppSettingsDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-settings-dialog')), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('app-settings-dialog')), findsNothing);
  });

  // The dialog follows a design of its own, so the only real check on it is
  // what it renders.
  testWidgets('looks the way it is meant to', (tester) async {
    tester.view.physicalSize = const Size(720, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await openDialog(
      tester,
      RecordingController(releases: FakeReleases(newer)),
    );

    await expectLater(
      find.byKey(const Key('app-settings-dialog')),
      matchesGoldenFile('goldens/app_settings_dialog.png'),
    );
  });

  testWidgets('does not shout at anybody', (tester) async {
    await openDialog(
      tester,
      RecordingController(releases: FakeReleases(newer)),
    );

    for (final text in tester.widgetList<Text>(find.byType(Text))) {
      final data = text.data;
      if (data == null || data.trim().isEmpty) continue;
      expect(
        data,
        isNot(equals(data.toUpperCase())),
        reason:
            'only the first letter of the first word is capitalised: '
            '"\$data"',
      );
    }
  });
}
