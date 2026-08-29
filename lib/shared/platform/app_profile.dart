/// Which installation directory this running copy owns.
///
/// DaySeven can run more than once at a time so that two accounts can be
/// signed in side by side — which is the only way to watch a Knowledge Base
/// replicate without two machines. Two copies sharing one directory would
/// fight over `dayseven.json`, `security.log` and the signed-in session, so
/// each copy takes a *profile*: a directory it owns for its lifetime.
///
/// Slot 0 is the directory the app has always used, and it keeps the library's
/// own session storage. An existing installation therefore reads and writes
/// exactly what it did before this file existed — no migration, and nobody is
/// signed out by upgrading.
///
/// Ownership is an open file descriptor holding an exclusive lock, not a pid
/// written into a file. The operating system drops the lock when the process
/// dies however it dies, so a crash never leaves a slot that looks taken.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/backend/profile_session_storage.dart';

/// The environment variable a new instance is launched with.
const String kProfileModeVariable = 'DAYSEVEN_PROFILE';

/// How many concurrent copies are supported. Beyond this, refusing is kinder
/// than silently sharing a directory.
const int kMaxProfileSlots = 8;

/// Whether this copy wants its own identity or the usual one.
enum ProfileMode {
  /// Use slot 0, sharing it with any copy already running. The same account,
  /// the same settings, a second window on the same work.
  shared,

  /// Take a slot of this copy's own, with its own login.
  fresh,
}

/// Reads the mode a new instance was launched with.
ProfileMode profileModeFromEnvironment([Map<String, String>? environment]) =>
    (environment ?? Platform.environment)[kProfileModeVariable] == 'new'
    ? ProfileMode.fresh
    : ProfileMode.shared;

/// Where a slot's files live. Slot 0 is the historical location.
Directory profileDirectoryFor(Directory root, int slot) => slot == 0
    ? root
    : Directory(p.join(root.path, 'profiles', '$slot'));

class ProfileUnavailableException implements Exception {
  const ProfileUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Attempts an exclusive lock, answering null when somebody else holds it.
typedef ProfileLockAttempt = Future<RandomAccessFile?> Function(File lockFile);

Future<RandomAccessFile?> _lockExclusively(File lockFile) async {
  try {
    await lockFile.parent.create(recursive: true);
    // Append rather than write: there is no reason to truncate a file another
    // process is holding open.
    final handle = await lockFile.open(mode: FileMode.append);
    try {
      handle.lockSync(FileLock.exclusive);
    } on Object {
      await handle.close();
      return null;
    }
    return handle;
  } on FileSystemException {
    return null;
  }
}

class AppProfile {
  AppProfile({
    required this.slot,
    required this.directory,
    required this.root,
    RandomAccessFile? lock,
  }) : _lock = lock;

  final int slot;

  /// Where this copy keeps `dayseven.json`, `security.log` and, above slot 0,
  /// its session.
  final Directory directory;

  /// The application support directory shared by every slot.
  final Directory root;

  /// Held open for the life of the process. Never closed: closing it is what
  /// releases the claim.
  // ignore: unused_field
  final RandomAccessFile? _lock;

  bool get isPrimary => slot == 0;

  /// Claims a slot.
  ///
  /// [ProfileMode.shared] always answers slot 0, whether or not another copy
  /// already has it — sharing is the point of that mode. [ProfileMode.fresh]
  /// takes the lowest slot nobody is holding.
  static Future<AppProfile> acquire({
    ProfileMode mode = ProfileMode.shared,
    Future<Directory> Function()? supportDirectory,
    ProfileLockAttempt? tryLock,
    int maxSlots = kMaxProfileSlots,
  }) async {
    final resolve = supportDirectory ?? getApplicationSupportDirectory;
    final attempt = tryLock ?? _lockExclusively;
    final root = await resolve();
    await root.create(recursive: true);

    if (mode == ProfileMode.shared) {
      // Take slot 0's lock when it is free so `otherInstancesRunning` can
      // answer, but do not require it: this mode shares by design.
      final directory = profileDirectoryFor(root, 0);
      await directory.create(recursive: true);
      return AppProfile(
        slot: 0,
        directory: directory,
        root: root,
        lock: await attempt(_lockFileIn(directory)),
      );
    }

    for (var slot = 1; slot < maxSlots; slot++) {
      final directory = profileDirectoryFor(root, slot);
      await directory.create(recursive: true);
      final lock = await attempt(_lockFileIn(directory));
      if (lock == null) continue;
      return AppProfile(
        slot: slot,
        directory: directory,
        root: root,
        lock: lock,
      );
    }

    throw const ProfileUnavailableException(
      'DaySeven is already running as many times as it supports. Close one of '
      'the open windows and try again.',
    );
  }

  static File _lockFileIn(Directory directory) =>
      File(p.join(directory.path, 'instance.lock'));

  /// The session storage for this profile.
  ///
  /// Slot 0 answers a plain options object, leaving `localStorage` null, so
  /// `Supabase.initialize` builds the same SharedPreferences-backed storage it
  /// always has and an existing login survives the upgrade untouched.
  FlutterAuthClientOptions authOptions() {
    if (isPrimary) return const FlutterAuthClientOptions();
    return FlutterAuthClientOptions(
      localStorage: FileLocalStorage.inDirectory(directory),
      pkceAsyncStorage: FileGotrueAsyncStorage.inDirectory(directory),
    );
  }

  /// Whether any other slot is currently claimed.
  ///
  /// Asked before installing an update: two copies swapping the application
  /// bundle at once would replace it underneath each other.
  Future<bool> otherInstancesRunning({
    ProfileLockAttempt? tryLock,
    int maxSlots = kMaxProfileSlots,
  }) async {
    final attempt = tryLock ?? _lockExclusively;
    for (var candidate = 0; candidate < maxSlots; candidate++) {
      if (candidate == slot) continue;
      final directory = profileDirectoryFor(root, candidate);
      if (!await directory.exists()) continue;
      final lock = await attempt(_lockFileIn(directory));
      if (lock == null) return true;
      // Nobody held it. Release immediately so the slot stays available.
      await lock.close();
    }
    return false;
  }
}

/// The profile this copy owns, or null when the caller never established one —
/// tests, and any embedder that did not run `main`. Null means the historical
/// location, so nothing has to know about profiles in order to keep working.
final appProfileProvider = Provider<AppProfile?>((ref) => null);
