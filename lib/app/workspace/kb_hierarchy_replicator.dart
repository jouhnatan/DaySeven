/// Replicates folder hierarchy and document contents between the local
/// Knowledge Base bundle and the canonical Postgres store.
///
/// The app historically assumed both collaborators already had identical
/// copies and only exchanged single-document publishes/proposals. Creating
/// `Awayside/Untitled.md` locally therefore never appeared on a peer that
/// had no `Awayside` folder until that peer ran Sync and the
/// ledger + path conflict checks allowed the write. This replicator is the
/// explicit, testable place that ensures missing hierarchy and file data are
/// created when absent and kept in sync otherwise.
///
/// It is deliberately in `app/workspace/` (not `shared/`) because it
/// composes `shared/backend/` repositories with `app/workspace/` ledger and
/// controllers, which `scripts/check_layers.sh` forbids `shared/` from importing.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/app/workspace/sync_results.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/kb/bundle.dart';

class _LocalDocument {
  const _LocalDocument({required this.path, required this.document});

  final String path;
  final BlockDocument document;
}

class _LocalDocumentInventory {
  const _LocalDocumentInventory({
    required this.documents,
    required this.byId,
    required this.duplicateIds,
  });

  final List<_LocalDocument> documents;
  final Map<String, _LocalDocument> byId;
  final Set<String> duplicateIds;
}

Future<_LocalDocumentInventory> _readLocalDocuments(KnowledgeBase kb) async {
  final documents = <_LocalDocument>[];
  final byId = <String, _LocalDocument>{};
  final duplicateIds = <String>{};
  final tree = await kb.readTree();
  for (final path in documentPathsIn(tree)) {
    final document = await kb.readDocument(path);
    final local = _LocalDocument(path: path, document: document);
    documents.add(local);
    if (byId.containsKey(document.id)) duplicateIds.add(document.id);
    byId.putIfAbsent(document.id, () => local);
  }
  return _LocalDocumentInventory(
    documents: documents,
    byId: byId,
    duplicateIds: duplicateIds,
  );
}

/// Keeps a local folder hierarchy and its document contents in sync with the
/// canonical store. Single-document `publishOpenDocument` stays the explicit
/// document action; this class is the bulk, idempotent reconciler that manual
/// Knowledge Base Sync can call to replicate missing hierarchy and data.
///
/// Behaviour matches `SharingController.pullRemoteChanges` / `pushLocalChanges`
/// but is extracted so it can be unit-tested and reused. In particular:
///
/// * Missing parent folders implied by `snapshot.path` (e.g. `Awayside/`) are
///   created via `File(...).parent.create(recursive:true)` before writing.
/// * Divergent local files (contentHash != ledger) are preserved and counted
///   as conflicts – never overwritten.
/// * Ledger is the merge base; remote `current_revision_id` is the source of
///   truth.
/// * Empty folders are not stored remotely – only document paths create
///   folders, by design.
class KbHierarchyReplicator {
  const KbHierarchyReplicator(this._ref);
  final Ref _ref;

  /// Ensures every canonical document (and its implied folder hierarchy) exists
  /// locally with the correct contents, unless a divergent local file must be
  /// preserved. Returns counts of created/updated, conflicts, and recovered
  /// deletions. Mirrors `SharingController.pullRemoteChanges` but is the
  /// canonical hierarchy-replicating implementation.
  Future<SyncPullResult> ensureLocalMatchesRemote({
    KbSession? sessionOverride,
    DocumentRepository? documentsOverride,
    AssetRepository? assetsOverride,
    KbRole? roleOverride,
  }) async {
    final session = sessionOverride ?? _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }
    final KbRole role;
    if (roleOverride != null) {
      role = roleOverride;
    } else {
      role = await _ref.read(kbRoleProvider.future);
    }
    if (role == KbRole.local) {
      throw const SyncException('This Knowledge Base is not shared.');
    }
    if (role == KbRole.invited) {
      throw const SyncException('Accept the invitation first.');
    }

    await _ref.read(documentControllerProvider.notifier).flush();
    final kb = session.kb;
    final ledger = await SyncLedger.open(kb);
    final DocumentRepository documents =
        documentsOverride ?? _ref.read(documentRepositoryProvider);
    final AssetRepository assets =
        assetsOverride ?? _ref.read(assetRepositoryProvider);
    final localInventory = await _readLocalDocuments(kb);
    final snapshots = await documents.snapshot(kb.manifest.kbId);
    final remoteIds = snapshots.map((item) => item.document.id).toSet();
    var updated = 0;
    var conflicts = 0;
    var recovered = 0;
    final conflictIds = <String>{};

    for (final snapshot in snapshots) {
      final documentId = snapshot.document.id;

      if (localInventory.duplicateIds.contains(documentId)) {
        conflicts++;
        conflictIds.add(documentId);
        continue;
      }

      final previous = ledger.document(documentId);
      final local = localInventory.byId[documentId];
      final target = File(kb.absolutePathFor(snapshot.path));

      if (local != null) {
        final remoteUnchanged =
            previous != null &&
            previous.revisionId == snapshot.revisionId &&
            previous.path == snapshot.path;

        if (remoteUnchanged) {
          if (local.path == snapshot.path &&
              local.document.contentHash == previous.contentHash) {
            if (previous.protection != snapshot.protection) {
              await ledger.record(
                document: local.document,
                revisionId: snapshot.revisionId,
                path: snapshot.path,
                protection: snapshot.protection,
              );
            }
          } else if (previous.protection != snapshot.protection) {
            await ledger.record(
              document: local.document,
              revisionId: snapshot.revisionId,
              path: local.path,
              protection: snapshot.protection,
            );
          }
          continue;
        }

        if (previous == null) {
          if (local.document.contentHash == snapshot.document.contentHash &&
              local.path == snapshot.path) {
            await ledger.record(
              document: local.document,
              revisionId: snapshot.revisionId,
              path: snapshot.path,
              protection: snapshot.protection,
            );
          } else {
            conflicts++;
            conflictIds.add(documentId);
          }
          continue;
        }

        final localMoved = local.path != previous.path;
        final localModified =
            local.document.contentHash != previous.contentHash;
        final remoteMoved = snapshot.path != previous.path;
        final remoteModified = snapshot.revisionId != previous.revisionId;

        if (localModified ||
            (localMoved && remoteMoved) ||
            (localMoved && remoteModified) ||
            (local.path != snapshot.path && await target.exists())) {
          conflicts++;
          conflictIds.add(documentId);
          continue;
        }

        await Directory(p.dirname(target.path)).create(recursive: true);
        await assets.downloadMissing(kb: kb, document: snapshot.document);
        await kb.writeDocument(snapshot.path, snapshot.document);
        if (local.path != snapshot.path) {
          final oldFile = File(kb.absolutePathFor(local.path));
          if (await oldFile.exists()) {
            await oldFile.delete();
          }
        }
        await ledger.record(
          document: snapshot.document,
          revisionId: snapshot.revisionId,
          path: snapshot.path,
          protection: snapshot.protection,
        );
        final open = _ref.read(documentControllerProvider);
        if (open?.document.id == snapshot.document.id) {
          await _ref
              .read(documentControllerProvider.notifier)
              .open(snapshot.path);
        }
        updated++;
        continue;
      }

      if (await target.exists()) {
        conflicts++;
        conflictIds.add(documentId);
        continue;
      }

      final oldPath = previous?.path ?? snapshot.path;
      final oldFile = File(kb.absolutePathFor(oldPath));

      await Directory(p.dirname(target.path)).create(recursive: true);
      await assets.downloadMissing(kb: kb, document: snapshot.document);
      await kb.writeDocument(snapshot.path, snapshot.document);
      if (oldPath != snapshot.path && await oldFile.exists()) {
        await oldFile.delete();
      }
      await ledger.record(
        document: snapshot.document,
        revisionId: snapshot.revisionId,
        path: snapshot.path,
        protection: snapshot.protection,
      );
      final open = _ref.read(documentControllerProvider);
      if (open?.document.id == snapshot.document.id) {
        await _ref
            .read(documentControllerProvider.notifier)
            .open(snapshot.path);
      }
      updated++;
    }

    // Canonically deleted files are moved under .settings/recovery, never
    // destroyed. Locally modified files stay in place and count as conflicts.
    for (final entry in ledger.documents.toList()) {
      if (remoteIds.contains(entry.key)) continue;

      if (localInventory.duplicateIds.contains(entry.key)) {
        conflicts++;
        conflictIds.add(entry.key);
        continue;
      }

      final localDoc = localInventory.byId[entry.key];
      final actualPath = localDoc?.path ?? entry.value.path;
      final localFile = File(kb.absolutePathFor(actualPath));

      if (!await localFile.exists()) {
        await ledger.remove(entry.key);
        continue;
      }
      try {
        final local = localDoc?.document ?? await kb.readDocument(actualPath);
        if (local.contentHash != entry.value.contentHash) {
          conflicts++;
          conflictIds.add(entry.key);
          continue;
        }
      } on Object {
        conflicts++;
        conflictIds.add(entry.key);
        continue;
      }
      final recovery = File(
        p.join(
          kb.settingsPath,
          'recovery',
          entry.key,
          p.basename(localFile.path),
        ),
      );
      await recovery.parent.create(recursive: true);
      await localFile.rename(recovery.path);
      if (_ref.read(documentControllerProvider)?.document.id == entry.key) {
        _ref.read(documentControllerProvider.notifier).close(save: false);
      }
      await ledger.remove(entry.key);
      recovered++;
    }

    if (updated > 0 || recovered > 0) {
      await session.index.rebuild();
      await _ref.read(kbControllerProvider.notifier).refreshTree();
    }
    final open = _ref.read(documentControllerProvider);
    if (open != null && conflictIds.contains(open.document.id)) {
      _ref
          .read(differencesControllerProvider.notifier)
          .markConflict(
            open.document.id,
            'A collaborator published a revision while this local copy had '
            'unpublished edits. Your local copy was kept.',
          );
    }
    return SyncPullResult(
      updated: updated,
      conflicts: conflicts,
      recoveredDeletions: recovered,
    );
  }

  /// Ensures every local document (and its hierarchy) is reflected remotely
  /// when the local copy has changed since the last sync base. Respects
  /// optimistic locking: if the canonical revision moved, the document counts
  /// as a conflict and is left untouched.
  Future<SyncPushResult> ensureRemoteMatchesLocal({
    KbSession? sessionOverride,
    DocumentRepository? documentsOverride,
    AssetRepository? assetsOverride,
    KbRole? roleOverride,
  }) async {
    final session = sessionOverride ?? _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }
    final KbRole role;
    if (roleOverride != null) {
      role = roleOverride;
    } else {
      role = await _ref.read(kbRoleProvider.future);
    }
    if (role.publishingRank == null) {
      throw const SyncException('Your role cannot publish local changes.');
    }

    await _ref.read(documentControllerProvider.notifier).flush();
    final kb = session.kb;
    final kbId = kb.manifest.kbId;
    final DocumentRepository documents =
        documentsOverride ?? _ref.read(documentRepositoryProvider);
    final AssetRepository assets =
        assetsOverride ?? _ref.read(assetRepositoryProvider);
    final ledger = await SyncLedger.open(kb);
    final remote = await documents.snapshot(kbId);
    final remoteById = {
      for (final snapshot in remote) snapshot.document.id: snapshot,
    };
    final localInventory = await _readLocalDocuments(kb);
    final seenIds = <String>{};
    var published = 0;
    var proposed = 0;
    var unchanged = 0;
    var conflicts = 0;

    for (final local in localInventory.documents) {
      final document = local.document;
      final path = local.path;

      if (!seenIds.add(document.id)) continue;

      if (localInventory.duplicateIds.contains(document.id)) {
        conflicts++;
        continue;
      }

      final snapshot = remoteById[document.id];
      final previous = ledger.document(document.id);

      if (snapshot != null &&
          snapshot.document.contentHash == document.contentHash &&
          snapshot.path == path) {
        await ledger.record(
          document: document,
          revisionId: snapshot.revisionId,
          path: path,
          protection: snapshot.protection,
        );
        unchanged++;
        continue;
      }

      if (snapshot != null) {
        final localChanged =
            previous == null ||
            previous.contentHash != document.contentHash ||
            previous.path != path;
        if (!localChanged) {
          unchanged++;
          continue;
        }
        if (previous == null || previous.revisionId != snapshot.revisionId) {
          conflicts++;
          continue;
        }
      }

      if (remote.any((s) => s.path == path && s.document.id != document.id)) {
        conflicts++;
        continue;
      }

      await assets.uploadReferenced(kb: kb, document: document);
      final receipt = await documents.publishChange(
        kbId: kbId,
        relativePath: path,
        document: document,
        expectedCurrentRevisionId: snapshot?.revisionId,
      );
      if (receipt.wasPublished) {
        await ledger.record(
          document: document,
          revisionId: receipt.id,
          path: path,
          protection: snapshot?.protection,
        );
        published++;
      } else {
        proposed++;
      }
    }

    return SyncPushResult(
      published: published,
      proposed: proposed,
      unchanged: unchanged,
      conflicts: conflicts,
    );
  }

  /// Bidirectional reconcile: first pulls missing remote hierarchy/data, then
  /// pushes local hierarchy/data. Used by the manual Knowledge Base Sync
  /// control.
  Future<ReconcileResult> reconcile({
    KbSession? sessionOverride,
    DocumentRepository? documentsOverride,
    AssetRepository? assetsOverride,
  }) async {
    final role = await _ref.read(kbRoleProvider.future);
    final pull = await ensureLocalMatchesRemote(
      sessionOverride: sessionOverride,
      documentsOverride: documentsOverride,
      assetsOverride: assetsOverride,
      roleOverride: role,
    );
    final push = await ensureRemoteMatchesLocal(
      sessionOverride: sessionOverride,
      documentsOverride: documentsOverride,
      assetsOverride: assetsOverride,
      roleOverride: role,
    );
    return ReconcileResult(pull: pull, push: push);
  }
}

// Provider for the replicator. SharingController and UI can read this
// instead of duplicating pull/push logic.
final kbHierarchyReplicatorProvider = Provider(
  (ref) => KbHierarchyReplicator(ref),
);

// Re-export sharing symbols that define these result types so callers
// do not need to import sharing.dart just for the types. The replicator
// itself imports them via sharing.dart to avoid duplication.
