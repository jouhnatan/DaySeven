import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/features/app_settings/ui/app_settings_dialog.dart';
import 'package:dayseven/shared/platform/app_update.dart';
import 'package:dayseven/shared/ui/controls.dart';
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
  Widget? knowledgeBasePanel,
  AppSettingsSection section = AppSettingsSection.appearance,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appUpdateProvider.overrideWith((ref) => controller)],
      child: MaterialApp(
        theme: dsTheme(),
        home: Scaffold(
          body: AppSettingsDialog(
            developerOptions: developerOptions,
            knowledgeBasePanel: knowledgeBasePanel,
            initialSection: section,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Moves to a section the way a person does, through the switcher.
Future<void> selectSection(
  WidgetTester tester,
  AppSettingsSection section,
) async {
  await tester.tap(find.byKey(Key('app-settings-section-${section.name}')));
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
    await selectSection(tester, AppSettingsSection.about);

    // Label left, value right: the name of the thing, then what it is set to.
    expect(find.text('DaySeven'), findsOneWidget);
    expect(find.text('1.3.2'), findsOneWidget);
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

    // Developer options are a region of their own, reached from the switcher.
    expect(find.text('CRDT collaboration'), findsNothing);
    await selectSection(tester, AppSettingsSection.developer);

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
      section: AppSettingsSection.developer,
    );

    expect(find.text('Connected'), findsOneWidget);
    expect(find.textContaining('Durable cursor 42'), findsOneWidget);
    expect(find.textContaining('3 incoming update(s) queued'), findsOneWidget);
    expect(find.text('Policy signing needs attention'), findsOneWidget);
    expect(find.text('An incoming update was refused'), findsOneWidget);

    final collabState = find.byKey(const Key('app-settings-collaboration-state'));
    final policyBlock = find.byKey(const Key('app-settings-policy-signing'));
    expect(
      tester.getTopLeft(policyBlock).dy - tester.getBottomLeft(collabState).dy,
      12.0,
    );

    final republish = find.byKey(const Key('app-settings-republish-policy'));
    await tester.ensureVisible(republish);
    await tester.pumpAndSettle();
    await tester.tap(republish);
    await tester.pumpAndSettle();
    expect(republished, isTrue);
  });

  testWidgets('a failed policy republish exposes a copyable error', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await openDialog(
      tester,
      RecordingController(),
      developerOptions: AppSettingsDeveloperOptions(
        showWorkspaceMetadata: true,
        crdtCollaboration: true,
        setShowWorkspaceMetadata: (_) async {},
        setCrdtCollaboration: (_) async {},
        collaborationHealth: AppSettingsCollaborationHealth.connected,
        policyDetail: 'This device does not hold the published key.',
        republishPolicy: () async => throw StateError('policy write refused'),
      ),
      section: AppSettingsSection.developer,
    );

    final republish = find.byKey(
      const Key('app-settings-republish-policy'),
    );
    await tester.ensureVisible(republish);
    await tester.tap(republish);
    await tester.pumpAndSettle();

    expect(find.textContaining('policy write refused'), findsOneWidget);
    final copy = find.byKey(const Key('copy-error-message'));
    await tester.ensureVisible(copy);
    await tester.pumpAndSettle();
    await tester.tap(copy);
    expect(copied, contains('policy write refused'));
  });

  group('describeLastChecked', () {
    final now = DateTime(2026, 8, 27, 14, 30);

    test('says nothing has been checked before the first check runs', () {
      // Not "checked today at midnight": the state defaults to no timestamp
      // rather than to a freshness nothing established.
      expect(describeLastChecked(null, now: now), 'Not checked yet');
    });

    test('names today, yesterday, and the date before that', () {
      expect(
        describeLastChecked(DateTime(2026, 8, 27, 9, 14), now: now),
        'Checked today at 9:14 AM',
      );
      expect(
        describeLastChecked(DateTime(2026, 8, 26, 18, 5), now: now),
        'Checked yesterday at 6:05 PM',
      );
      expect(
        describeLastChecked(DateTime(2026, 8, 20, 11, 0), now: now),
        'Checked 20 August at 11:00 AM',
      );
    });

    test('reads midnight and noon the way a clock does', () {
      expect(
        describeLastChecked(DateTime(2026, 8, 27, 0, 7), now: now),
        'Checked today at 12:07 AM',
      );
      expect(
        describeLastChecked(DateTime(2026, 8, 27, 12, 0), now: now),
        'Checked today at 12:00 PM',
      );
    });

    test('counts calendar days, not elapsed hours', () {
      // 23:50 last night to 00:10 this morning is twenty minutes, but it is
      // still yesterday, and saying "today" would be wrong.
      expect(
        describeLastChecked(
          DateTime(2026, 8, 26, 23, 50),
          now: DateTime(2026, 8, 27, 0, 10),
        ),
        'Checked yesterday at 11:50 PM',
      );
    });
  });

  testWidgets('the switcher lists only the regions this build actually has', (
    tester,
  ) async {
    await openDialog(tester, RecordingController());

    expect(
      find.byKey(const Key('app-settings-section-appearance')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('app-settings-section-updates')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('app-settings-section-about')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('app-settings-section-knowledgeBase')),
      findsNothing,
    );

    await openDialog(
      tester,
      RecordingController(),
      knowledgeBasePanel: const Text('kb panel'),
    );

    expect(
      find.byKey(const Key('app-settings-section-knowledgeBase')),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('app-settings-section-developer')),
      findsNothing,
      reason: 'developer options are absent from an ordinary build',
    );
  });

  testWidgets('the switcher moves between sections and shows where you are', (
    tester,
  ) async {
    await openDialog(
      tester,
      RecordingController(),
      knowledgeBasePanel: const Text('kb panel'),
    );

    expect(find.text('kb panel'), findsNothing);
    expect(find.text('Gradient background'), findsOneWidget);

    await selectSection(tester, AppSettingsSection.knowledgeBase);

    expect(find.text('kb panel'), findsOneWidget);
    expect(find.text('Gradient background'), findsNothing);

    // The strip itself holds the answer to "where am I": its raised cell is
    // the section on screen.
    expect(
      tester
          .widget<DsSegmented<AppSettingsSection>>(
            find.byType(DsSegmented<AppSettingsSection>),
          )
          .value,
      AppSettingsSection.knowledgeBase,
    );
  });

  testWidgets('opens straight onto the section it was asked for', (
    tester,
  ) async {
    await openDialog(
      tester,
      RecordingController(),
      knowledgeBasePanel: const Text('kb panel'),
      section: AppSettingsSection.knowledgeBase,
    );

    // The gear beside the Knowledge Base tree lands here rather than making
    // somebody find the section themselves.
    expect(find.text('kb panel'), findsOneWidget);
  });

  testWidgets('falls back to Appearance when a section is not in this build', (
    tester,
  ) async {
    await openDialog(
      tester,
      RecordingController(),
      section: AppSettingsSection.knowledgeBase,
    );

    // Nothing supplied a Knowledge Base panel, so that section does not exist
    // and the switcher would otherwise have had nothing selected.
    expect(find.text('Gradient background'), findsOneWidget);
  });

  // Solway labels regions; it never carries a value. A version and a build
  // number are values, so they are set in the sans with tabular figures — the
  // digits have to line up between the rows stacked above and below them.
  testWidgets('sets every value in the sans, with figures that line up', (
    tester,
  ) async {
    await openDialog(tester, RecordingController());
    await selectSection(tester, AppSettingsSection.about);

    for (final label in [
      'DaySeven',
      '1.3.2',
      'Build 7',
    ]) {
      final style = tester.widget<Text>(find.text(label)).style;
      expect(style?.fontFamily, kUiFontFamily, reason: '"$label" is not sans');
    }

    for (final label in ['1.3.2', 'Build 7']) {
      expect(
        tester.widget<Text>(find.text(label)).style?.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: '"$label" carries digits that have to align',
      );
    }

    // The dialog title is the one thing here that names a region.
    expect(
      tester.widget<Text>(find.text('Settings')).style?.fontFamily,
      kUiHeaderFontFamily,
    );
  });

  // Fern means where you are, or this commits. In this dialog only the update
  // action commits, so it is the only thing allowed to be a block of it.
  testWidgets('spends the accent only on the action that commits', (
    tester,
  ) async {
    await openDialog(tester, RecordingController());

    final fernFills = tester
        .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
        .map((c) => (c.decoration as BoxDecoration?)?.color)
        .where((color) => color == CF.fern || color == CF.fernHover)
        .length;

    expect(
      fernFills,
      lessThanOrEqualTo(2),
      reason: 'at most two fern elements belong on one surface',
    );
  });

  // The dialog exists so that the answer arrives before the button, rather
  // than only after somebody presses it.
  testWidgets('checks on open and reports being current', (tester) async {
    await openDialog(tester, RecordingController(releases: FakeReleases(same)));

    await selectSection(tester, AppSettingsSection.updates);
    expect(find.text('Up to date'), findsOneWidget);
    // A state that can go stale carries the moment it was established, so
    // that a fresh answer can be told from one sitting there since yesterday.
    expect(find.textContaining('Checked today at'), findsOneWidget);
    expect(find.text('Check now'), findsOneWidget);
  });

  testWidgets('update rows do not duplicate the status card separator', (
    tester,
  ) async {
    await openDialog(tester, RecordingController());
    await selectSection(tester, AppSettingsSection.updates);

    for (final label in ['Install updates automatically', 'Channel']) {
      final row = find.ancestor(
        of: find.text(label),
        matching: find.byType(DsSettingRow),
      );
      expect(row, findsOneWidget);
      expect(tester.widget<DsSettingRow>(row).first, isTrue);
    }
  });

  testWidgets('checks on open and names a newer version', (tester) async {
    await openDialog(
      tester,
      RecordingController(releases: FakeReleases(newer)),
    );

    await selectSection(tester, AppSettingsSection.updates);
    expect(find.text('Version 1.4.0'), findsOneWidget);
    expect(find.text('Build 8'), findsOneWidget);
    // A button says what will happen, with the object it happens to, so that
    // the label still means something read on its own.
    expect(find.text('Install 1.4.0'), findsOneWidget);
  });

  testWidgets('installs the release when asked', (tester) async {
    final controller = RecordingController(releases: FakeReleases(newer));
    await openDialog(tester, controller);
    await selectSection(tester, AppSettingsSection.updates);

    await tester.tap(find.byKey(const Key('app-settings-run-updates')));
    await tester.pumpAndSettle();

    expect(controller.requested.single.version, const AppVersion('1.4.0', 8));
  });

  testWidgets('locks the button and shows progress while downloading', (
    tester,
  ) async {
    final controller = RecordingController();
    await openDialog(tester, controller);
    await selectSection(tester, AppSettingsSection.updates);

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
    await selectSection(tester, AppSettingsSection.updates);

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
    await selectSection(tester, AppSettingsSection.updates);

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
    await selectSection(tester, AppSettingsSection.updates);

    controller.show(const UpdateFailed(newer, 'The disk was full.'));
    await tester.pump();

    expect(find.text('The disk was full.'), findsOneWidget);
    expect(find.text('Download'), findsOneWidget);
  });

  testWidgets('says so when the build has no server to check against', (
    tester,
  ) async {
    await openDialog(tester, RecordingController(enabled: false));
    await selectSection(tester, AppSettingsSection.updates);

    expect(find.text('No server configured'), findsOneWidget);
    expect(find.textContaining('published to Supabase'), findsOneWidget);
    // The version is still worth seeing, now in About.
    await selectSection(tester, AppSettingsSection.about);
    expect(find.text('1.3.2'), findsOneWidget);
  });

  testWidgets('Done closes the dialog', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appUpdateProvider.overrideWith((ref) => RecordingController()),
        ],
        child: MaterialApp(
          theme: dsTheme(),
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
    tester.view.physicalSize = const Size(800, 620);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Photographed with everything it can show: the switcher needs more than
    // one region before it is a switcher at all.
    await openDialog(
      tester,
      RecordingController(releases: FakeReleases(newer)),
      knowledgeBasePanel: const SizedBox.shrink(),
      developerOptions: AppSettingsDeveloperOptions(
        showWorkspaceMetadata: false,
        crdtCollaboration: false,
        setShowWorkspaceMetadata: (_) async {},
        setCrdtCollaboration: (_) async {},
        collaborationHealth: AppSettingsCollaborationHealth.off,
      ),
    );

    await expectLater(
      find.byKey(const Key('app-settings-dialog')),
      matchesGoldenFile('goldens/app_settings_dialog.png'),
    );
  });

  testWidgets('pads the settings content area from the left and right sides', (
    tester,
  ) async {
    await openDialog(tester, RecordingController());

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(
      scroll.padding,
      const EdgeInsets.symmetric(horizontal: DsSpace.xl),
      reason:
          'the settings view area must have comfortable horizontal breathing room',
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
      // A version or a build number is all digits, and reads as its own
      // uppercase. Only text with letters in it can be shouting.
      if (!data.contains(RegExp('[A-Za-z]'))) continue;
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
