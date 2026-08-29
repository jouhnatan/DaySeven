/// Which directory a running copy claims, and why slot 0 must not move.
///
/// The lock primitive itself is not tested here and cannot honestly be: fcntl
/// locks do not conflict within a single process, and isolates share one. What
/// is tested is the slot arithmetic and the choice of session storage, through
/// the seam. The primitive is verified by launching the app twice.
library;

import 'dart:io';

import 'package:dayseven/shared/backend/profile_session_storage.dart';
import 'package:dayseven/shared/platform/app_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dayseven-profile-');
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// A lock that refuses the named slots, standing in for copies already
  /// running.
  ProfileLockAttempt lockRefusing(Set<int> taken) => (file) async {
    final slot = _slotOf(file, root);
    if (taken.contains(slot)) return null;
    await file.parent.create(recursive: true);
    return file.open(mode: FileMode.append);
  };

  group('profile directories', () {
    test('slot 0 is the historical location, so nothing moves', () {
      expect(profileDirectoryFor(root, 0).path, root.path);
    });

    test('later slots are nested, and never collide', () {
      expect(profileDirectoryFor(root, 1).path, p.join(root.path, 'profiles', '1'));
      expect(profileDirectoryFor(root, 2).path, p.join(root.path, 'profiles', '2'));
      expect(
        profileDirectoryFor(root, 1).path,
        isNot(profileDirectoryFor(root, 2).path),
      );
    });
  });

  group('mode from the environment', () {
    test('only the explicit value asks for a fresh identity', () {
      expect(
        profileModeFromEnvironment({kProfileModeVariable: 'new'}),
        ProfileMode.fresh,
      );
    });

    test('an absent or unrecognised value shares, which is the safe default', () {
      expect(profileModeFromEnvironment({}), ProfileMode.shared);
      expect(
        profileModeFromEnvironment({kProfileModeVariable: 'shared'}),
        ProfileMode.shared,
      );
      expect(
        profileModeFromEnvironment({kProfileModeVariable: 'anything else'}),
        ProfileMode.shared,
      );
    });
  });

  group('claiming a slot', () {
    test('sharing takes slot 0 even when another copy already holds it', () async {
      final profile = await AppProfile.acquire(
        mode: ProfileMode.shared,
        supportDirectory: () async => root,
        tryLock: lockRefusing({0}),
      );

      expect(profile.slot, 0);
      expect(profile.directory.path, root.path);
      expect(profile.isPrimary, isTrue);
    });

    test('a fresh identity skips slots that are taken', () async {
      final profile = await AppProfile.acquire(
        mode: ProfileMode.fresh,
        supportDirectory: () async => root,
        tryLock: lockRefusing({1, 2}),
      );

      expect(profile.slot, 3);
      expect(profile.directory.existsSync(), isTrue);
      expect(profile.isPrimary, isFalse);
    });

    test('a fresh identity never takes slot 0, which belongs to the first copy',
        () async {
      final profile = await AppProfile.acquire(
        mode: ProfileMode.fresh,
        supportDirectory: () async => root,
        tryLock: lockRefusing(const {}),
      );

      expect(profile.slot, 1);
    });

    test('refuses rather than silently sharing when every slot is taken',
        () async {
      await expectLater(
        AppProfile.acquire(
          mode: ProfileMode.fresh,
          supportDirectory: () async => root,
          tryLock: lockRefusing({1, 2, 3}),
          maxSlots: 4,
        ),
        throwsA(
          isA<ProfileUnavailableException>().having(
            (e) => e.message,
            'message',
            contains('already running'),
          ),
        ),
      );
    });
  });

  group('session storage', () {
    test('slot 0 keeps the library default, so nobody is signed out', () async {
      final profile = await AppProfile.acquire(
        mode: ProfileMode.shared,
        supportDirectory: () async => root,
        tryLock: lockRefusing(const {}),
      );

      // A null localStorage is what makes Supabase.initialize build the same
      // SharedPreferences storage this installation already uses.
      expect(profile.authOptions().localStorage, isNull);
      expect(profile.authOptions().pkceAsyncStorage, isNull);
    });

    test('a fresh profile gets its own session, which is what holds a second '
        'account', () async {
      final profile = await AppProfile.acquire(
        mode: ProfileMode.fresh,
        supportDirectory: () async => root,
        tryLock: lockRefusing(const {}),
      );

      final storage = profile.authOptions().localStorage;
      expect(storage, isA<FileLocalStorage>());
      expect(
        (storage! as FileLocalStorage).file.path,
        startsWith(profile.directory.path),
      );
      expect(profile.authOptions().pkceAsyncStorage, isA<FileGotrueAsyncStorage>());
    });
  });
}

int _slotOf(File lockFile, Directory root) {
  final relative = p.relative(lockFile.parent.path, from: root.path);
  if (relative == '.') return 0;
  return int.parse(p.basename(relative));
}
