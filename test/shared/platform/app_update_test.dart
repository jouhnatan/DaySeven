import 'package:flutter_test/flutter_test.dart';

import 'package:dayseven/shared/platform/app_update.dart';

/// Answers from the release feed without a server, in the same shape as the
/// hand-written fakes used elsewhere in the suite.
class FakeReleases implements ReleaseDataSource {
  FakeReleases(this.release);

  AppRelease? release;
  Object? error;
  int calls = 0;

  @override
  Future<AppRelease?> currentRelease(String platform) async {
    calls++;
    if (error case final failure?) throw failure;
    return release;
  }
}

const validSha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, dynamic> row({
  String version = '1.4.0',
  int build = 6,
  String platform = 'macos',
  Object? sha = validSha,
  Object? size = 1024,
  Object? downloadUrl = 'https://example.test/DaySeven-macos.zip',
  String? minimumVersion,
  String? notes,
}) => {
  'platform': platform,
  'version': version,
  'build_number': build,
  'download_url': downloadUrl,
  'install_url': 'https://example.test/DaySeven.dmg',
  'sha256': sha,
  'size_bytes': size,
  'release_notes': notes,
  'minimum_version': minimumVersion,
};

/// Exposes the state a StateNotifier otherwise keeps to itself and its
/// listeners, so a test can assert on it without subscribing.
class TestController extends AppUpdateController {
  TestController(super.releases, super.version, {required super.enabled});

  AppUpdateState get current => state;
}

TestController controllerFor(
  FakeReleases releases, {
  AppVersion current = const AppVersion('1.3.0', 5),
  bool enabled = true,
}) => TestController(releases, Future.value(current), enabled: enabled);

void main() {
  group('AppVersion', () {
    test('orders by name before build number', () {
      expect(const AppVersion('1.4.0', 1) > const AppVersion('1.3.0', 99), isTrue);
      expect(const AppVersion('1.3.10', 1) > const AppVersion('1.3.9', 1), isTrue);
      expect(const AppVersion('2.0.0', 0) > const AppVersion('1.99.99', 99), isTrue);
    });

    // The whole reason the build number is carried around: without it these
    // two are the same release, and neither Windows nor the app would see an
    // update between them.
    test('distinguishes builds of the same version', () {
      expect(const AppVersion('1.3.0', 6) > const AppVersion('1.3.0', 5), isTrue);
      expect(const AppVersion('1.3.0', 5) > const AppVersion('1.3.0', 6), isFalse);
      expect(const AppVersion('1.3.0', 5) == const AppVersion('1.3.0', 5), isTrue);
    });

    test('rejects anything that is not three numbers', () {
      expect(AppVersion.tryParse('1.3', 1), isNull);
      expect(AppVersion.tryParse('1.3.0-beta', 1), isNull);
      expect(AppVersion.tryParse('', 1), isNull);
      expect(AppVersion.tryParse('1.3.0', 1), isNotNull);
    });
  });

  group('AppRelease.fromRow', () {
    test('reads a complete row', () {
      final release = AppRelease.fromRow(row(notes: 'Fixes'))!;

      expect(release.version, const AppVersion('1.4.0', 6));
      expect(release.platform, 'macos');
      expect(release.sizeBytes, 1024);
      expect(release.releaseNotes, 'Fixes');
      expect(release.installUrl, 'https://example.test/DaySeven.dmg');
      expect(release.minimumVersion, isNull);
    });

    test('normalises the checksum so comparison is not case-dependent', () {
      final release = AppRelease.fromRow(row(sha: validSha.toUpperCase()))!;
      expect(release.sha256, validSha);
    });

    // A row missing any of these describes a release nothing could install.
    // Returning null makes that "no update", not a broken one offered anyway.
    test('rejects rows that could not be installed', () {
      expect(AppRelease.fromRow(row(downloadUrl: null)), isNull);
      expect(AppRelease.fromRow(row(downloadUrl: '')), isNull);
      expect(AppRelease.fromRow(row(sha: null)), isNull);
      expect(AppRelease.fromRow(row(size: null)), isNull);
      expect(AppRelease.fromRow(row(size: 0)), isNull);
      expect(AppRelease.fromRow(row(version: 'latest')), isNull);
    });

    test('reads a minimum version when one is set', () {
      final release = AppRelease.fromRow(row(minimumVersion: '1.2.0'))!;

      expect(release.isMandatoryFor(const AppVersion('1.1.9', 1)), isTrue);
      expect(release.isMandatoryFor(const AppVersion('1.2.0', 0)), isFalse);
      expect(release.isMandatoryFor(const AppVersion('1.3.0', 5)), isFalse);
    });

    test('leaves the update advisory when no minimum is set', () {
      final release = AppRelease.fromRow(row())!;
      expect(release.isMandatoryFor(const AppVersion('1.0.0', 1)), isFalse);
    });
  });

  group('check', () {
    test('offers a newer release', () async {
      final releases = FakeReleases(AppRelease.fromRow(row()));
      final controller = controllerFor(releases);

      await controller.check();

      final state = controller.current;
      expect(state, isA<UpdateAvailable>());
      expect((state as UpdateAvailable).release.version,
          const AppVersion('1.4.0', 6));
      expect(state.mandatory, isFalse);
    });

    test('stays quiet when the feed matches the running build', () async {
      final releases = FakeReleases(
        AppRelease.fromRow(row(version: '1.3.0', build: 5)),
      );
      final controller = controllerFor(releases);

      await controller.check();

      expect(controller.current, isA<UpToDate>());
    });

    test('stays quiet when the feed is behind the running build', () async {
      final releases = FakeReleases(
        AppRelease.fromRow(row(version: '1.2.0', build: 1)),
      );
      final controller = controllerFor(releases);

      await controller.check();

      expect(controller.current, isA<UpToDate>());
    });

    test('marks the update mandatory below the minimum version', () async {
      final releases = FakeReleases(
        AppRelease.fromRow(row(minimumVersion: '1.3.5')),
      );
      final controller = controllerFor(releases);

      await controller.check();

      expect((controller.current as UpdateAvailable).mandatory, isTrue);
    });

    // The check only runs because somebody asked for it, so a failure has to
    // be distinguishable from "you are up to date" — otherwise the app answers
    // a question it could not actually answer.
    test('reports a failing feed rather than claiming to be current', () async {
      final releases = FakeReleases(null)..error = Exception('offline');
      final controller = controllerFor(releases);

      await controller.check();

      expect(controller.current, isA<UpdateCheckFailed>());
      expect(
        (controller.current as UpdateCheckFailed).message,
        contains('offline'),
      );
    });

    test('does not ask when there is no server configured', () async {
      final releases = FakeReleases(AppRelease.fromRow(row()));
      final controller = controllerFor(releases, enabled: false);

      await controller.check();

      expect(releases.calls, 0);
      expect(controller.current, isA<UpdateCheckFailed>());
    });
  });

  group('DownloadingUpdate', () {
    test('reports progress against the published size', () {
      final release = AppRelease.fromRow(row(size: 200))!;
      expect(DownloadingUpdate(release, 50).fraction, 0.25);
      expect(DownloadingUpdate(release, 200).fraction, 1.0);
    });
  });
}
