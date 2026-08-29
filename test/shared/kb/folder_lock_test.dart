/// Claiming a Knowledge Base folder.
///
/// The lock primitive is not exercised here and cannot honestly be: advisory
/// locks do not conflict within one process. What is tested is that the claim
/// is taken and released cleanly, and that the file it leaves behind stays out
/// of the way of everything that walks the folder.
library;

import 'dart:io';

import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/kb/folder_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory folder;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('dayseven-folder-lock-');
  });

  tearDown(() async {
    if (folder.existsSync()) await folder.delete(recursive: true);
  });

  test('claiming a folder creates the lock inside .settings', () async {
    final lock = await KbFolderLock.tryAcquire(folder.path);
    addTearDown(() => lock?.release());

    expect(lock, isNotNull);
    expect(
      File(
        p.join(folder.path, kSettingsDirName, kFolderLockFileName),
      ).existsSync(),
      isTrue,
    );
  });

  test('a released folder can be claimed again', () async {
    // Reopening the same Knowledge Base in the same window must work, which is
    // why the controller releases before it acquires.
    final first = await KbFolderLock.tryAcquire(folder.path);
    expect(first, isNotNull);
    await first!.release();

    final second = await KbFolderLock.tryAcquire(folder.path);
    addTearDown(() => second?.release());
    expect(second, isNotNull);
  });

  test('releasing twice is safe', () async {
    final lock = await KbFolderLock.tryAcquire(folder.path);
    await lock!.release();
    await lock.release();
  });

  test('the lock file never reaches the tree the person sees', () async {
    final kb = await KnowledgeBase.create(folder: folder.path, name: 'Locked');
    final lock = await KbFolderLock.tryAcquire(folder.path);
    addTearDown(() => lock?.release());

    final tree = await kb.readTree(includeMetadata: true);

    expect(
      walkKbTree(tree).map((node) => node.name),
      isNot(contains(kFolderLockFileName)),
      reason: '.settings/ is skipped, so the claim stays invisible',
    );
  });
}
