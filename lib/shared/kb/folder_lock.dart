/// Which running copy has a Knowledge Base folder open.
///
/// Two copies editing one folder is the one combination that destroys work.
/// They would hold independent Yjs documents rooted in the same snapshot and
/// each write the whole thing back over the other, and the shared temporary
/// file used for that write can publish a spliced `workspace.bin` that will
/// not load at all. Neither is recoverable, and neither announces itself.
///
/// So a folder is claimed while it is open. The claim is an exclusive lock on
/// an open file descriptor rather than a pid written into a file: the
/// operating system releases it however the process dies, so a crash never
/// leaves a folder that looks taken.
///
/// The lock file lives in `.settings/`, which the tree walk, the filesystem
/// watcher and synchronisation all already skip, so nothing else has to learn
/// about it.
///
/// Advisory locking is unreliable over SMB and NFS. This protects folders on
/// local disks, which is where a Knowledge Base is meant to live.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:dayseven/shared/kb/bundle.dart';

const String kFolderLockFileName = 'open.lock';

class KbFolderLock {
  KbFolderLock._(this.folder, this._handle);

  final String folder;
  final RandomAccessFile _handle;

  /// Claims [folder], or answers null when another copy already holds it.
  ///
  /// The folder must already be a Knowledge Base: `.settings/` is created when
  /// the bundle is opened, so a folder that never becomes one is not left with
  /// a stray lock file in it.
  static Future<KbFolderLock?> tryAcquire(String folder) async {
    final file = File(p.join(folder, kSettingsDirName, kFolderLockFileName));
    try {
      await file.parent.create(recursive: true);
      final handle = await file.open(mode: FileMode.append);
      try {
        handle.lockSync(FileLock.exclusive);
      } on Object {
        await handle.close();
        return null;
      }
      return KbFolderLock._(folder, handle);
    } on FileSystemException {
      // An unwritable folder cannot be claimed. Treating that as "taken" would
      // be a confusing lie; treat it as free and let the real open fail with a
      // message about the real problem.
      return null;
    }
  }

  Future<void> release() async {
    try {
      await _handle.close();
    } on Object {
      // Already gone. The lock died with the descriptor either way.
    }
  }
}
