/// Shared sync result types used by [SharingController] and
/// [KbHierarchyReplicator].
library;

class SyncPullResult {
  const SyncPullResult({
    required this.updated,
    required this.conflicts,
    required this.recoveredDeletions,
  });
  final int updated;
  final int conflicts;
  final int recoveredDeletions;
}

class SyncPushResult {
  const SyncPushResult({
    required this.published,
    this.proposed = 0,
    required this.unchanged,
    required this.conflicts,
  });

  final int published;
  final int proposed;
  final int unchanged;
  final int conflicts;
}

class ReconcileResult {
  const ReconcileResult({required this.pull, required this.push});
  final SyncPullResult pull;
  final SyncPushResult push;
}
