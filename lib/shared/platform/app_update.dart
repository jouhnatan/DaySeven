/// Keeping the installed application up to date.
///
/// Both platforms work the same way, because on both of them DaySeven is
/// installed by unpacking an archive rather than by anything the operating
/// system manages. `app_releases` in Supabase is the source of truth: it says
/// which build is current, and the app compares its own version against it
/// when the person asks it to, from Menu -> Run updates.
///
/// Applying an update means replacing the files the running process was
/// started from, which cannot be done by that process. So every path here ends
/// the same way: unpack beside the install, write a small script that waits for
/// this process to exit, hand it off, and quit. The script does the swap and
/// reopens the app.
library;

import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/platform/app_profile.dart';
import 'package:dayseven/shared/platform/install_location.dart';

/// A version as the pubspec writes it: `1.3.0+5`.
///
/// The build number is half the identity, not a footnote: two releases of
/// `1.3.0` are told apart only by it.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.name, this.build);

  final String name;
  final int build;

  static AppVersion? tryParse(String name, int build) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(name)) return null;
    return AppVersion(name, build);
  }

  List<int> get _parts => name.split('.').map(int.parse).toList();

  @override
  int compareTo(AppVersion other) {
    final mine = _parts;
    final theirs = other._parts;
    for (var i = 0; i < 3; i++) {
      final difference = mine[i].compareTo(theirs[i]);
      if (difference != 0) return difference;
    }
    return build.compareTo(other.build);
  }

  bool operator >(AppVersion other) => compareTo(other) > 0;
  bool operator <(AppVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && other.name == name && other.build == build;

  @override
  int get hashCode => Object.hash(name, build);

  @override
  String toString() => '$name+$build';
}

/// One row of `app_releases`.
class AppRelease {
  const AppRelease({
    required this.platform,
    required this.version,
    required this.downloadUrl,
    required this.sha256,
    required this.sizeBytes,
    this.installUrl,
    this.releaseNotes,
    this.minimumVersion,
  });

  final String platform;
  final AppVersion version;

  /// The archive the updater fetches.
  final String downloadUrl;

  /// What a person opens by hand — the `.dmg` on macOS, the same archive on
  /// Windows. The fallback for every path where updating in place cannot
  /// proceed.
  final String? installUrl;

  final String sha256;
  final int sizeBytes;
  final String? releaseNotes;

  /// Below this, the update stops being advisory. Null leaves every update
  /// optional, which is the normal case.
  final AppVersion? minimumVersion;

  static AppRelease? fromRow(Map<String, dynamic> row) {
    final version = AppVersion.tryParse(
      '${row['version']}',
      (row['build_number'] as num?)?.toInt() ?? -1,
    );
    final downloadUrl = row['download_url'] as String?;
    final sha256 = row['sha256'] as String?;
    final size = (row['size_bytes'] as num?)?.toInt();

    // A row missing any of these describes a release nothing could install, so
    // it is treated as no release rather than as a broken one.
    if (version == null ||
        version.build < 0 ||
        downloadUrl == null ||
        downloadUrl.isEmpty ||
        sha256 == null ||
        size == null ||
        size <= 0) {
      return null;
    }

    final minimum = row['minimum_version'] as String?;

    return AppRelease(
      platform: '${row['platform']}',
      version: version,
      downloadUrl: downloadUrl,
      installUrl: row['install_url'] as String?,
      sha256: sha256.toLowerCase(),
      sizeBytes: size,
      releaseNotes: row['release_notes'] as String?,
      minimumVersion: minimum == null ? null : AppVersion.tryParse(minimum, 0),
    );
  }

  bool isNewerThan(AppVersion current) => version > current;

  /// True when the running build is old enough that the release feed says it
  /// should no longer be treated as a version worth staying on.
  bool isMandatoryFor(AppVersion current) {
    final minimum = minimumVersion;
    return minimum != null && current < minimum;
  }
}

/// The name this platform goes by in the release feed.
String? get currentReleasePlatform => switch (Platform.operatingSystem) {
  'windows' => 'windows',
  'macos' => 'macos',
  _ => null,
};

/// Where releases are read from. An interface so tests can answer without a
/// server, in the same shape as the repository seams elsewhere in the app.
abstract class ReleaseDataSource {
  Future<AppRelease?> currentRelease(String platform);
}

class SupabaseReleases implements ReleaseDataSource {
  const SupabaseReleases();

  @override
  Future<AppRelease?> currentRelease(String platform) async {
    final row = await supabase
        .from('app_releases')
        .select()
        .eq('platform', platform)
        .eq('channel', 'stable')
        .eq('is_current', true)
        .maybeSingle();

    return row == null ? null : AppRelease.fromRow(row);
  }
}

final releaseDataSourceProvider = Provider<ReleaseDataSource>(
  (ref) => const SupabaseReleases(),
);

/// Reads the running build's version. Injectable because the plugin channel is
/// not available in a plain widget test.
final currentVersionProvider = FutureProvider<AppVersion>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return AppVersion(info.version, int.tryParse(info.buildNumber) ?? 0);
});

sealed class AppUpdateState {
  const AppUpdateState();
}

/// Nothing to do: either the check has not run, or it found nothing newer.
class UpToDate extends AppUpdateState {
  const UpToDate([this.checkedAt]);

  /// When the feed last answered. "Up to date" is only true as of a moment,
  /// and a state that can go stale has to say when it was established — so
  /// this is null until a check has actually run, rather than defaulting to
  /// now and claiming a freshness nothing verified.
  final DateTime? checkedAt;
}

class CheckingForUpdate extends AppUpdateState {
  const CheckingForUpdate();
}

class UpdateAvailable extends AppUpdateState {
  const UpdateAvailable(this.release, {required this.mandatory});
  final AppRelease release;
  final bool mandatory;
}

class DownloadingUpdate extends AppUpdateState {
  const DownloadingUpdate(this.release, this.receivedBytes);
  final AppRelease release;
  final int receivedBytes;

  /// Null until the download reports a length, so the UI can show an
  /// indeterminate bar rather than a wrong one.
  double? get fraction =>
      release.sizeBytes <= 0 ? null : receivedBytes / release.sizeBytes;
}

/// Downloaded and verified; the swap happens as the app exits.
class InstallingUpdate extends AppUpdateState {
  const InstallingUpdate(this.release);
  final AppRelease release;
}

/// The check itself could not be made — offline, or the feed did not answer.
///
/// Distinct from [UpToDate] because this is only ever reached when somebody
/// asked. Reporting "you are up to date" to a question the app could not
/// actually answer would be a lie.
class UpdateCheckFailed extends AppUpdateState {
  const UpdateCheckFailed(this.message);
  final String message;
}

class UpdateFailed extends AppUpdateState {
  const UpdateFailed(this.release, this.message);
  final AppRelease release;
  final String message;
}

/// Raised when the update cannot be applied in place. Always carries something
/// worth showing: every one of these ends with the user being offered the
/// manual download instead.
class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;

  @override
  String toString() => message;
}

class AppUpdateController extends StateNotifier<AppUpdateState> {
  AppUpdateController(
    this._releases,
    this._currentVersion, {
    required this.enabled,
  }) : super(const UpToDate());

  final ReleaseDataSource _releases;
  final Future<AppVersion> _currentVersion;

  /// Whether there is a server to ask. Passed in rather than read from
  /// [isSupabaseConfigured] directly so a test can exercise the check without
  /// build-time credentials — the same reason the data source is an interface.
  final bool enabled;

  /// The step that replaces the install and quits. Held as a field rather than
  /// called directly so a test can observe the install being requested without
  /// the test process exiting.
  Future<void> Function(AppRelease, String) installer = installUpdate;

  /// Whether another copy is running. A field for the same reason [installer]
  /// is: a test needs to answer it without launching a second application.
  Future<bool> Function() otherInstancesRunning = () async => false;

  Future<void> check() async {
    final platform = currentReleasePlatform;
    // Collaboration needs a server, and so does this; without one there is no
    // feed to read.
    if (platform == null || !enabled) {
      state = const UpdateCheckFailed(
        'DaySeven was built without a server to check for updates against.',
      );
      return;
    }

    state = const CheckingForUpdate();
    try {
      final release = await _releases.currentRelease(platform);
      final current = await _currentVersion;

      if (release == null || !release.isNewerThan(current)) {
        state = UpToDate(DateTime.now());
        return;
      }

      state = UpdateAvailable(
        release,
        mandatory: release.isMandatoryFor(current),
      );
    } catch (error) {
      state = UpdateCheckFailed(describeError(error));
    }
  }

  /// Downloads the release and hands it to the platform's installer.
  Future<void> download(AppRelease release) async {
    if (currentReleasePlatform == null) return;

    // On macOS an app outside /Applications is an unmanaged copy, and
    // replacing it would leave the person with two DaySevens. The check is a
    // no-op on Windows, where the install directory is wherever it was
    // unpacked and any of them is as legitimate as another.
    final location = checkInstallLocation();
    if (!location.isCorrect) {
      state = UpdateFailed(
        release,
        'DaySeven can only update itself from the Applications folder. '
        'Move it there, or download the new version by hand.',
      );
      return;
    }

    // Two copies swapping the application bundle would replace it underneath
    // each other, and the staging sweep deletes the other's workspace.
    if (await otherInstancesRunning()) {
      state = UpdateFailed(
        release,
        'Another DaySeven window is open. Close it before installing an '
        'update, so the two copies do not replace the application underneath '
        'each other.',
      );
      return;
    }

    Directory? workspace;
    try {
      state = DownloadingUpdate(release, 0);
      workspace = await Directory.systemTemp.createTemp('dayseven-update-');
      final archive = File(p.join(workspace.path, 'DaySeven-macos.zip'));

      // A successful install ends with this process gone and the swap script
      // still reading from its workspace, so nothing can clean that one up at
      // the time. Any *other* workspace is therefore finished with, and this is
      // the one moment there is a running app to notice.
      _sweepOldWorkspaces(keep: workspace.path);

      await _fetch(
        release.downloadUrl,
        archive,
        onProgress: (received) {
          if (mounted) state = DownloadingUpdate(release, received);
        },
      );

      // The feed publishes the hash; checking it here is what makes an
      // interrupted or substituted download fail loudly instead of replacing
      // a working app with a broken one.
      final actual = await sha256.bind(archive.openRead()).first;
      if (actual.toString() != release.sha256) {
        throw const UpdateException(
          'The downloaded update did not match the published checksum.',
        );
      }

      if (!mounted) return;
      state = InstallingUpdate(release);
      await installer(release, archive.path);
    } catch (error) {
      // The workspace is only cleaned up on failure. On success the swap
      // script is still reading from it as this process exits.
      if (workspace != null) {
        await workspace.delete(recursive: true).catchError((_) => workspace!);
      }
      if (mounted) {
        state = UpdateFailed(
          release,
          error is UpdateException ? error.message : describeError(error),
        );
      }
    }
  }

  /// Streams to disk rather than buffering: the archive is tens of megabytes,
  /// and a byte count is the only honest progress signal available.
  static Future<void> _fetch(
    String url,
    File destination, {
    required void Function(int received) onProgress,
  }) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw UpdateException(
          'The update could not be downloaded (HTTP ${response.statusCode}).',
        );
      }

      final sink = destination.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close(force: true);
    }
  }
}

/// Unpacks the archive and arranges for the install to be replaced.
Future<void> installUpdate(AppRelease release, String archivePath) async {
  if (Platform.isMacOS) return installMacOSUpdate(release, archivePath);
  if (Platform.isWindows) return installWindowsUpdate(release, archivePath);
  throw const UpdateException(
    'DaySeven does not know how to update itself on this platform.',
  );
}

/// macOS: replace the application bundle.
///
/// The bundle cannot be replaced while the process is running out of it, so
/// this ends by starting a detached script and quitting. The script waits for
/// the process to go, moves the new bundle into place, and reopens the app.
Future<void> installMacOSUpdate(AppRelease release, String archivePath) async {
  final workspace = p.dirname(archivePath);
  final unpacked = p.join(workspace, 'unpacked');

  // `ditto`, not the archive package: an .app is a tree of symlinks and
  // extended attributes, and anything that flattens those produces a bundle
  // that will not launch.
  await _run('/usr/bin/ditto', ['-x', '-k', archivePath, unpacked]);

  final staged = Directory(unpacked)
      .listSync()
      .whereType<Directory>()
      .firstWhere(
        (entry) => entry.path.endsWith('.app'),
        orElse: () => throw const UpdateException(
          'The downloaded update did not contain an application bundle.',
        ),
      )
      .path;

  // Downloads arrive quarantined. Left in place, the replaced app would be
  // treated as freshly downloaded and refuse to open without a prompt.
  await _run('/usr/bin/xattr', ['-dr', 'com.apple.quarantine', staged]);

  // .../DaySeven.app/Contents/MacOS/dayseven -> .../DaySeven.app
  final target = p.dirname(p.dirname(p.dirname(Platform.resolvedExecutable)));
  if (!target.endsWith('.app')) {
    throw const UpdateException(
      'DaySeven is not running from an application bundle, so it cannot '
      'replace itself.',
    );
  }

  await _requireWritable(p.dirname(target));

  final quotedTarget = _shellQuote(target);
  final quotedStaged = _shellQuote(staged);
  final quotedWorkspace = _shellQuote(workspace);

  // `$pid` is this process's id, from dart:io — interpolated in as a literal
  // number, so the script waits for *this* app and nothing else.
  final script = File(p.join(workspace, 'swap.sh'));
  await script.writeAsString('''
#!/bin/sh
# Replaces the running DaySeven with the freshly downloaded one, then reopens
# it. Written and started by the app itself; deletes itself when done.
set -e

# Wait for the old process to exit. The bundle cannot be replaced underneath a
# running app, and that app is quitting as this script starts.
while kill -0 $pid 2>/dev/null; do sleep 0.2; done

# Move the old bundle aside rather than deleting it, so a failure at the next
# step leaves a working app rather than nothing at all.
rm -rf $quotedTarget.previous
mv $quotedTarget $quotedTarget.previous
if ! mv $quotedStaged $quotedTarget; then
  mv $quotedTarget.previous $quotedTarget
  open $quotedTarget
  exit 1
fi

rm -rf $quotedTarget.previous
open $quotedTarget
rm -rf $quotedWorkspace
''');
  await _run('/bin/chmod', ['+x', script.path]);

  // Detached, so it outlives the process that started it.
  await Process.start('/bin/sh', [
    script.path,
  ], mode: ProcessStartMode.detached);

  exit(0);
}

/// Windows: replace the contents of the install directory.
///
/// There is no bundle here, just the folder the zip was unpacked into, so the
/// swap is a mirror of one directory onto another. Windows will not let a
/// running executable be replaced at all, so as on macOS this hands off to a
/// script and quits.
///
/// Unlike macOS, it does not quit on trust. Starting the helper is the step
/// most likely to be refused by something outside the app's control, and this
/// process is the last one able to say so, so it waits for the helper to
/// report in and reports a failure instead of exiting into silence.
Future<void> installWindowsUpdate(
  AppRelease release,
  String archivePath,
) async {
  final workspace = p.dirname(archivePath);
  final staged = p.join(workspace, 'unpacked');

  // The archive package rather than a shelled-out Expand-Archive: a Windows
  // build is plain files with none of the symlinks or extended attributes that
  // make an .app need `ditto`, and this keeps the failure inside Dart.
  await extractFileToDisk(archivePath, staged);

  if (!File(p.join(staged, 'dayseven.exe')).existsSync()) {
    throw const UpdateException(
      'The downloaded update did not contain dayseven.exe.',
    );
  }

  // ...\\DaySeven\\dayseven.exe -> ...\\DaySeven
  final target = p.dirname(Platform.resolvedExecutable);
  await _requireWritable(target);

  final handoff = File(p.join(workspace, 'handoff-started'));
  final log = p.join(workspace, 'swap.log');

  final quotedTarget = _batchQuote(target);
  final quotedStaged = _batchQuote(staged);
  final quotedLog = _batchQuote(log);
  final quotedHandoff = _batchQuote(handoff.path);
  final quotedExe = _batchQuote(p.join(target, 'dayseven.exe'));

  final script = File(p.join(workspace, 'swap.cmd'));
  await script.writeAsString('''
@echo off
rem Replaces the running DaySeven with the freshly downloaded one, then reopens
rem it. Written and started by the app itself.

rem Written before anything that can fail. The app waits for this file and
rem refuses to quit without it, so a helper that never runs is reported rather
rem than leaving somebody with a closed app and no update.
> $quotedHandoff echo started

rem Wait for the old process to exit. Windows will not let a running executable
rem be replaced, and that process is quitting as this script starts. The floor
rem is unconditional so that the swap still waits if tasklist is unavailable
rem and the loop below falls through immediately.
ping -n 3 127.0.0.1 > nul

set _waited=0
:wait
tasklist /fi "PID eq $pid" /nh 2> nul | find "$pid" > nul || goto swap
set /a _waited+=1
if %_waited% GEQ 120 goto swap
ping -n 2 127.0.0.1 > nul
goto wait

:swap
rem /MIR so files dropped between versions do not linger. Nothing of the user's
rem lives here - documents are wherever they chose, and app state is in AppData -
rem so mirroring is safe.
robocopy $quotedStaged $quotedTarget /MIR /NFL /NDL /NJH /NJS /NP >> $quotedLog 2>&1

rem robocopy uses exit codes 0-7 for success; 8 and above are real failures.
if errorlevel 8 goto failed

start "" /d $quotedTarget $quotedExe
exit /b 0

:failed
>> $quotedLog echo swap failed - the install was left as it was.
start "" /d $quotedTarget $quotedExe
exit /b 1
''', flush: true);

  // cmd.exe rather than PowerShell. An unsigned executable spawning
  // `powershell -ExecutionPolicy Bypass -WindowStyle Hidden -File %TEMP%\\...`
  // and immediately exiting is indistinguishable from malware: anti-virus
  // blocks the process outright, and a machine-level execution policy beats
  // the `-ExecutionPolicy Bypass` switch anyway. Either way the app quit and
  // nothing replaced it. cmd.exe has no execution policy and no language mode
  // to fall foul of, and robocopy was doing the actual work regardless.
  //
  // Detached, so it outlives the process that started it. Detached also means
  // no console is allocated, so nothing flashes on screen.
  await Process.start('cmd.exe', [
    '/c',
    script.path,
  ], mode: ProcessStartMode.detached);

  // Only now is it safe to go. Quitting on the strength of Process.start alone
  // is what turned a blocked helper into a silent shutdown: this process is the
  // last thing able to report the failure, so it does not exit until the helper
  // has proven it is running.
  if (!await _handoffStarted(handoff)) {
    throw const UpdateException(
      'DaySeven could not start the helper that installs the update, most '
      'likely because anti-virus or a script policy blocked it. Nothing has '
      'been changed — download the new version by hand instead.',
    );
  }

  exit(0);
}

/// Waits for the swap script to report that it is running.
///
/// The script writes the file as its first action, so this resolves in
/// milliseconds when the hand-off worked at all. Returning false means the
/// helper never started, not that it started slowly.
Future<bool> _handoffStarted(File sentinel) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (DateTime.now().isBefore(deadline)) {
    if (sentinel.existsSync()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return false;
}

/// Single-quotes a path for /bin/sh, the way any path interpolated into a
/// generated script has to be.
String _shellQuote(String value) => "'${value.replaceAll("'", r"'\''")}'";

/// Double-quotes a path for cmd.exe.
///
/// Batch has no escape character inside a quoted string, so the characters it
/// cannot survive are rejected rather than mangled: `%` would expand as a
/// variable, and `"` would end the quoting. Neither can occur in a Windows path
/// that Windows itself produced, so this is a guard against generating a
/// broken script rather than a case anyone is expected to hit. `&`, `^` and `!`
/// are all literal inside quotes and need no handling.
String _batchQuote(String value) {
  if (value.contains('%') || value.contains('"')) {
    throw UpdateException(
      'DaySeven cannot update itself from a path containing " or %: $value',
    );
  }
  return '"$value"';
}

/// Removes update workspaces left behind by earlier runs.
///
/// The swap script cannot delete the directory it is being read from, so a
/// successful update always leaves one behind. Best effort in every direction:
/// a workspace still in use just fails to delete and is left where it is.
void _sweepOldWorkspaces({required String keep}) {
  try {
    for (final entry in Directory.systemTemp.listSync()) {
      if (entry is! Directory) continue;
      if (p.equals(entry.path, keep)) continue;
      if (!p.basename(entry.path).startsWith('dayseven-update-')) continue;
      try {
        entry.deleteSync(recursive: true);
      } on FileSystemException {
        // In use, or not this user's to delete.
      }
    }
  } on FileSystemException {
    // Not being able to sweep is never a reason to fail an update.
  }
}

/// Fails with something worth reading when the install cannot be written to —
/// most often DaySeven unpacked into Program Files on Windows, or installed by
/// another user on macOS.
Future<void> _requireWritable(String directory) async {
  final probe = File(p.join(directory, '.dayseven-write-probe'));
  try {
    await probe.writeAsString('');
    await probe.delete();
  } on FileSystemException {
    throw const UpdateException(
      'DaySeven does not have permission to replace its own files. Move it '
      'somewhere you can write to, or download the new version by hand.',
    );
  }
}

/// Hands a URL to the desktop, for the paths where the app cannot install the
/// update itself and the person has to fetch it by hand.
///
/// Done with the platform's own opener rather than a plugin: this is a
/// desktop-only application, and both commands are one line.
Future<void> openExternally(String url) async {
  if (Platform.isWindows) {
    // The empty argument is the window title `start` would otherwise take the
    // URL to be.
    await Process.run('cmd', ['/c', 'start', '', url]);
  } else if (Platform.isMacOS) {
    await Process.run('/usr/bin/open', [url]);
  }
}

Future<void> _run(String executable, List<String> arguments) async {
  final result = await Process.run(executable, arguments);
  if (result.exitCode != 0) {
    throw UpdateException(
      '${p.basename(executable)} failed: ${result.stderr}'.trim(),
    );
  }
}

final appUpdateProvider =
    StateNotifierProvider<AppUpdateController, AppUpdateState>((ref) {
      final profile = ref.watch(appProfileProvider);
      return AppUpdateController(
        ref.watch(releaseDataSourceProvider),
        ref.watch(currentVersionProvider.future),
        enabled: isSupabaseConfigured,
      )..otherInstancesRunning = profile == null
          ? (() async => false)
          : profile.otherInstancesRunning;
    });
