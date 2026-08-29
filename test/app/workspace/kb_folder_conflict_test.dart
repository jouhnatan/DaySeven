/// Opening a folder that another window already has.
///
/// Two copies editing one folder is the combination that loses work, so the
/// refusal has to be reliable and it has to say which folder it means.
library;

import 'dart:io';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/kb/folder_lock.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory folder;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    folder = await Directory.systemTemp.createTemp('dayseven-conflict-');
  });

  tearDown(() async {
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  test('a folder held by another window is refused by name', () async {
    // Standing in for a second copy of the application, which a single test
    // process cannot produce: advisory locks do not conflict with themselves.
    final container = ProviderContainer(
      overrides: [
        kbFolderLockProvider.overrideWithValue(
          (String folder) async => null,
        ),
        appStoreProvider.overrideWith(
          (ref) async => AppStore(File('${folder.path}.app-store.json')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(kbControllerProvider.notifier).openFolder(folder.path);

    final state = container.read(kbControllerProvider);
    expect(state, isA<AsyncError<KbSession?>>());

    final error = (state as AsyncError<KbSession?>).error;
    expect(error, isA<KbFolderBusyException>());
    expect(
      (error as KbFolderBusyException).message,
      allOf(
        contains(folder.path.split(Platform.pathSeparator).last),
        contains('another DaySeven'),
      ),
      reason: 'the person has to know which folder, and where it is open',
    );
  });

  test('a folder nobody holds opens as usual', () async {
    final container = ProviderContainer(
      overrides: [
        kbFolderLockProvider.overrideWithValue(KbFolderLock.tryAcquire),
        appStoreProvider.overrideWith(
          (ref) async => AppStore(File('${folder.path}.app-store.json')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(kbControllerProvider.notifier).openFolder(folder.path);

    expect(container.read(kbControllerProvider), isA<AsyncData<KbSession?>>());
    expect(container.read(kbControllerProvider).valueOrNull, isNotNull);
  });
}
