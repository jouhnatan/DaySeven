/// A stand-in for the canonical object store in tests that exercise the sync
/// paths. It answers snapshots from memory and records publishes, so no test
/// needs a network.
library;

import 'package:dayseven/shared/backend/object_repository.dart';

class FakeObjectRepository extends ObjectRepository {
  FakeObjectRepository({this.snapshots = const []});

  List<RemoteObjectSnapshot> snapshots;
  final List<RemoteObjectSnapshot> published = [];
  int publishCalls = 0;

  @override
  Future<List<RemoteObjectSnapshot>> snapshot(String kbId) async => snapshots;

  @override
  Future<String> publish({
    required String kbId,
    required String objectId,
    required String kind,
    required String path,
    required String title,
    required Map<String, Object?> content,
    required String contentHash,
    required String? expectedCurrentRevisionId,
  }) async {
    publishCalls++;
    final snapshot = RemoteObjectSnapshot(
      id: objectId,
      kind: kind,
      path: path,
      revisionId: 'object-revision-$publishCalls',
      content: content,
      contentHash: contentHash,
    );
    published.add(snapshot);
    snapshots = [
      for (final existing in snapshots)
        if (existing.id != objectId) existing,
      snapshot,
    ];
    return snapshot.revisionId;
  }
}
