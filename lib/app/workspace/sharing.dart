/// Explicitly publishing local working copies to a shared Knowledge Base.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
export 'package:dayseven/app/workspace/kb_role.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/document_protection.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/features/knowledge_base/data/kb_repository.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/domain/merge.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';
import 'package:dayseven/shared/blocks/blocks.dart';

class OpenDocumentPublishAction {
  const OpenDocumentPublishAction({
    required this.role,
    required this.protection,
    required this.willPropose,
  });

  final KbRole role;
  final DocumentProtection? protection;
  final bool willPropose;

  String get label => willPropose ? 'Propose' : 'Publish';
  bool get mayChangeProtection =>
      role.publishingRank != null &&
      (protection == null || role.meets(protection!.minimumPublishRole));
}

final openDocumentProtectionProvider = FutureProvider<DocumentProtection?>((
  ref,
) async {
  final documentId = ref.watch(
    documentControllerProvider.select((open) => open?.document.id),
  );
  final role = await ref.watch(kbRoleProvider.future);
  if (documentId == null || role == KbRole.local || role == KbRole.invited) {
    return null;
  }
  return ref.watch(documentRepositoryProvider).protection(documentId);
});

final openDocumentPublishActionProvider =
    FutureProvider<OpenDocumentPublishAction?>((ref) async {
      final documentId = ref.watch(
        documentControllerProvider.select((open) => open?.document.id),
      );
      final role = await ref.watch(kbRoleProvider.future);
      if (documentId == null || role.publishingRank == null) return null;
      final protection = await ref.watch(openDocumentProtectionProvider.future);
      return OpenDocumentPublishAction(
        role: role,
        protection: protection,
        willPropose:
            protection != null && !role.meets(protection.minimumPublishRole),
      );
    });

/// Instantiated by the shell. Realtime and focus are wake-up signals only;
/// [pullRemoteChanges] reads durable canonical rows and preserves divergent
/// local files.
final incomingCanonicalSyncProvider = Provider<void>((ref) {
  ref.listen<int>(canonicalSyncWakeProvider, (_, _) {
    unawaited(() async {
      try {
        await ref.read(sharingControllerProvider).pullRemoteChanges();
        ref.invalidate(openDocumentProtectionProvider);
        ref.invalidate(openDocumentPublishActionProvider);
      } on Object {
        // Manual Sync latest remains available and surfaces its error. A wake
        // signal must never replace durable state with an assumed empty value.
      }
    }());
  });
});

class SharingController {
  const SharingController(this._ref);

  final Ref _ref;

  /// Shares the open Knowledge Base: registers it and publishes every document
  /// in it, so a collaborator has a full history to start from.
  Future<void> shareOpenKb() async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }

    await _ref
        .read(kbRepositoryProvider)
        .createRemote(
          kbId: session.kb.manifest.kbId,
          name: session.kb.manifest.name,
        );

    final documents = _ref.read(documentRepositoryProvider);
    final assets = _ref.read(assetRepositoryProvider);
    final ledger = await SyncLedger.open(session.kb);
    final tree = await session.kb.readTree();
    for (final path in documentPathsIn(tree)) {
      final document = await session.kb.readDocument(path);
      await assets.uploadReferenced(kb: session.kb, document: document);
      final revisionId = await documents.publish(
        kbId: session.kb.manifest.kbId,
        relativePath: path,
        document: document,
      );
      await ledger.record(
        document: document,
        revisionId: revisionId,
        path: path,
      );
    }
    _ref.invalidate(kbRoleProvider);
  }

  Future<void> invite(String username, CollaborationRole role) async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;
    await _ref
        .read(kbRepositoryProvider)
        .invite(kbId: session.kb.manifest.kbId, username: username, role: role);
  }

  Future<void> acceptInvitationIntoFolder(
    KbInvitation invitation,
    String folder,
  ) async {
    final directory = Directory(folder);
    if (!await directory.exists()) await directory.create(recursive: true);
    if (!await directory.list(followLinks: false).isEmpty) {
      throw const SyncException(
        'Choose an empty folder for this Knowledge Base.',
      );
    }

    await _ref.read(kbRepositoryProvider).acceptInvitation(invitation.kbId);
    final kb = await KnowledgeBase.create(
      folder: folder,
      name: invitation.name,
      kbId: invitation.kbId,
    );
    try {
      final snapshots = await _ref
          .read(documentRepositoryProvider)
          .snapshot(invitation.kbId);
      final ledger = await SyncLedger.open(kb);
      for (final snapshot in snapshots) {
        await _ref
            .read(assetRepositoryProvider)
            .downloadMissing(kb: kb, document: snapshot.document);
        await kb.writeDocument(snapshot.path, snapshot.document);
        await ledger.record(
          document: snapshot.document,
          revisionId: snapshot.revisionId,
          path: snapshot.path,
          protection: snapshot.protection,
        );
      }
    } finally {
      // Once accepted, keep the local bundle reachable even if a network
      // interruption made the first download partial. Sync latest can resume.
      await _ref.read(kbControllerProvider.notifier).openFolder(folder);
      _ref.invalidate(kbInvitationsProvider);
      _ref.invalidate(kbRoleProvider);
    }
  }

  /// Removes only the open Knowledge Base's Supabase mirror. The open folder,
  /// its manifest and every document on disk remain exactly where they are, so
  /// the same Knowledge Base can be shared again later.
  Future<void> deleteSharedKb() async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }

    await _ref
        .read(kbRepositoryProvider)
        .deleteRemote(session.kb.manifest.kbId);
    await _ref
        .read(differencesControllerProvider.notifier)
        .refresh(showLoading: false);
    _ref.invalidate(kbRoleProvider);
  }

  /// Publishes every locally changed document in the open Knowledge Base.
  ///
  /// This is intentionally separate from [pullRemoteChanges]: publishing is a
  /// visible owner/co-owner action, while downloading never treats this device
  /// as the source of truth. If the cloud moved since this local copy's last
  /// sync point, the local file is left untouched and reported as a conflict.
  Future<SyncPushResult> pushLocalChanges() async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }
    final role = await _ref.read(kbRoleProvider.future);
    if (role.publishingRank == null) {
      throw const SyncException('Your role cannot publish local changes.');
    }

    await _ref.read(documentControllerProvider.notifier).flush();
    final kb = session.kb;
    final kbId = kb.manifest.kbId;
    final documents = _ref.read(documentRepositoryProvider);
    final assets = _ref.read(assetRepositoryProvider);
    final ledger = await SyncLedger.open(kb);
    final remote = await documents.snapshot(kbId);
    final remoteById = {
      for (final snapshot in remote) snapshot.document.id: snapshot,
    };
    final tree = await kb.readTree();
    var published = 0;
    var proposed = 0;
    var unchanged = 0;
    var conflicts = 0;

    for (final path in documentPathsIn(tree)) {
      final document = await kb.readDocument(path);
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

  /// Explicitly sends the open local working copy to collaborators.
  ///
  /// The server decides atomically whether this is a canonical publish or a
  /// reviewed proposal. If canonical state moved, non-overlapping changes are
  /// three-way merged and retried once. Overlapping changes stay local.
  Future<SyncOutcome> publishOpenDocument({bool retryOnMove = true}) async {
    final session = _ref.read(kbSessionProvider);
    final open = _ref.read(documentControllerProvider);
    if (session == null || open == null) {
      throw const SyncException('Open a document first.');
    }

    // Whatever is on screen is what gets sent.
    await _ref.read(documentControllerProvider.notifier).flush();
    final currentOpen = _ref.read(documentControllerProvider) ?? open;
    final document = currentOpen.document;
    final relativePath = currentOpen.relativePath;

    final role = await _ref.read(kbRoleProvider.future);
    final kbId = session.kb.manifest.kbId;

    if (role.publishingRank == null) {
      throw const SyncException('Your role cannot edit this document.');
    }

    final documents = _ref.read(documentRepositoryProvider);
    final ledger = await SyncLedger.open(session.kb);
    var synced = ledger.document(document.id);
    var workingDocument = document;
    var workingPath = relativePath;
    var current = await documents.snapshotForDocument(document.id);

    if (current != null && synced == null) {
      final error = const SyncException(
        'This device has no sync base for the canonical document. Sync latest '
        'before publishing.',
      );
      _ref
          .read(differencesControllerProvider.notifier)
          .markConflict(document.id, error.message);
      throw error;
    }

    final differences = _ref.read(differencesControllerProvider.notifier);
    final protection = current?.protection ?? synced?.protection;
    final willPropose =
        protection != null && !role.meets(protection.minimumPublishRole);
    differences.markPublishing(document.id, willPropose: willPropose);

    try {
      if (synced != null &&
          current?.revisionId == synced.revisionId &&
          synced.contentHash == workingDocument.contentHash &&
          synced.path == workingPath) {
        differences.markPublished(document.id);
        return SyncOutcome.unchanged;
      }

      if (synced != null &&
          current != null &&
          current.revisionId != synced.revisionId) {
        final base = await documents.revision(synced.revisionId);
        if (base == null) {
          throw const SyncException(
            'The saved merge base is unavailable. Sync latest before publishing.',
          );
        }
        final merge = threeWayMerge(
          base: base.content,
          local: current.document,
          proposed: workingDocument,
        );
        final localRenamed = synced.path != workingPath;
        final remoteRenamed = synced.path != current.path;
        final pathConflict =
            localRenamed && remoteRenamed && workingPath != current.path;
        if (merge.hasConflicts || pathConflict) {
          final conflict = PublishConflict(
            documentId: document.id,
            base: base.content,
            canonical: current.document,
            canonicalRevisionId: current.revisionId,
            canonicalPath: current.path,
            protection: current.protection,
            local: workingDocument,
            localPath: workingPath,
            merged: merge.document,
            pathConflict: pathConflict,
          );
          differences.markConflict(
            document.id,
            'Canonical and local edits overlap. Your local copy was kept.',
          );
          throw conflict;
        }
        workingDocument = merge.document;
        if (!localRenamed) workingPath = current.path;
        synced = SyncedDocument(
          revisionId: current.revisionId,
          contentHash: current.document.contentHash,
          path: current.path,
          protection: current.protection,
        );
      }

      await _ref
          .read(assetRepositoryProvider)
          .uploadReferenced(kb: session.kb, document: workingDocument);
      final receipt = await documents.publishChange(
        kbId: kbId,
        relativePath: workingPath,
        document: workingDocument,
        expectedCurrentRevisionId: synced?.revisionId,
      );
      if (!receipt.wasPublished) {
        differences.markProposed(document.id, receipt.id);
        await differences.refresh(showLoading: false);
        return SyncOutcome.proposed;
      }

      if (workingDocument.contentHash != document.contentHash ||
          workingPath != relativePath) {
        await session.kb.writeDocument(workingPath, workingDocument);
        if (workingPath != relativePath) {
          final old = File(session.kb.absolutePathFor(relativePath));
          if (await old.exists()) await old.delete();
        }
        await session.index.rebuild();
        await _ref.read(kbControllerProvider.notifier).refreshTree();
        final openAfterMerge = _ref.read(documentControllerProvider);
        if (openAfterMerge?.document.id == document.id) {
          await _ref
              .read(documentControllerProvider.notifier)
              .open(workingPath);
        }
      }
      await ledger.record(
        document: workingDocument,
        revisionId: receipt.id,
        path: workingPath,
        protection: current?.protection ?? synced?.protection,
      );
      differences.markPublished(document.id);
      _ref.invalidate(openDocumentProtectionProvider);
      _ref.invalidate(openDocumentPublishActionProvider);
      return SyncOutcome.committed;
    } on PublishConflict {
      rethrow;
    } on Object catch (error) {
      if (retryOnMove && _isOptimisticMove(error)) {
        return publishOpenDocument(retryOnMove: false);
      }
      differences.markPublishError(document.id, error);
      rethrow;
    }
  }

  /// Kept as a source-compatible alias while callers migrate to the explicit
  /// protection-aware action.
  Future<SyncOutcome> publishOpenDocumentDirectly() => publishOpenDocument();

  bool _isOptimisticMove(Object error) =>
      error is PostgrestException && error.code == '40001';

  Future<DocumentProtection?> setOpenDocumentProtection(
    DocumentProtection? protection,
  ) async {
    final session = _ref.read(kbSessionProvider);
    final open = _ref.read(documentControllerProvider);
    if (session == null || open == null) {
      throw const SyncException('Open a document first.');
    }
    final role = await _ref.read(kbRoleProvider.future);
    if (role.publishingRank == null) {
      throw const SyncException('Your role cannot protect documents.');
    }
    final ledger = await SyncLedger.open(session.kb);
    final synced = ledger.document(open.document.id);
    if (synced == null) {
      throw const SyncException('Publish this document before protecting it.');
    }
    final updated = await _ref
        .read(documentRepositoryProvider)
        .setProtection(
          kbId: session.kb.manifest.kbId,
          documentId: open.document.id,
          protection: protection,
        );
    await ledger.record(
      document: open.document,
      revisionId: synced.revisionId,
      path: open.relativePath,
      protection: updated,
    );
    _ref.invalidate(openDocumentProtectionProvider);
    _ref.invalidate(openDocumentPublishActionProvider);
    return updated;
  }

  /// Resolves an overlapping publish after the user explicitly chooses which
  /// local content should be sent against the canonical revision they saw.
  Future<SyncOutcome> resolvePublishConflict(
    PublishConflict conflict, {
    required bool publishLocal,
  }) async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }
    final documents = _ref.read(documentRepositoryProvider);
    final latest = await documents.snapshotForDocument(conflict.documentId);
    if (latest == null || latest.revisionId != conflict.canonicalRevisionId) {
      throw const SyncException(
        'The canonical document changed again. Review the newest revision first.',
      );
    }

    if (!publishLocal) {
      await _ref
          .read(assetRepositoryProvider)
          .downloadMissing(kb: session.kb, document: latest.document);
      await session.kb.writeDocument(latest.path, latest.document);
      if (conflict.localPath != latest.path) {
        final old = File(session.kb.absolutePathFor(conflict.localPath));
        if (await old.exists()) await old.delete();
      }
      final ledger = await SyncLedger.open(session.kb);
      await ledger.record(
        document: latest.document,
        revisionId: latest.revisionId,
        path: latest.path,
        protection: latest.protection,
      );
      await session.index.rebuild();
      await _ref.read(kbControllerProvider.notifier).refreshTree();
      if (_ref.read(documentControllerProvider)?.document.id ==
          conflict.documentId) {
        await _ref.read(documentControllerProvider.notifier).open(latest.path);
      }
      _ref
          .read(differencesControllerProvider.notifier)
          .markPublished(conflict.documentId);
      return SyncOutcome.unchanged;
    }

    await _ref
        .read(assetRepositoryProvider)
        .uploadReferenced(kb: session.kb, document: conflict.local);
    final receipt = await documents.publishChange(
      kbId: session.kb.manifest.kbId,
      relativePath: conflict.localPath,
      document: conflict.local,
      expectedCurrentRevisionId: latest.revisionId,
    );
    final differences = _ref.read(differencesControllerProvider.notifier);
    if (!receipt.wasPublished) {
      differences.markProposed(conflict.documentId, receipt.id);
      return SyncOutcome.proposed;
    }
    final ledger = await SyncLedger.open(session.kb);
    await ledger.record(
      document: conflict.local,
      revisionId: receipt.id,
      path: conflict.localPath,
      protection: latest.protection,
    );
    differences.markPublished(conflict.documentId);
    return SyncOutcome.committed;
  }

  /// Mirrors a local deletion to the canonical KB, or turns it into a reviewed
  /// proposal for an editor. Call this before removing the local file.
  Future<void> syncDeletion(String relativePath) async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;
    final role = await _ref.read(kbRoleProvider.future);
    if (role == KbRole.local) return;
    if (role == KbRole.reviewer) {
      throw const SyncException('Reviewers cannot delete documents.');
    }
    if (role == KbRole.invited) {
      throw const SyncException('Accept the invitation first.');
    }

    final document = await session.kb.readDocument(relativePath);
    final documents = _ref.read(documentRepositoryProvider);
    final ledger = await SyncLedger.open(session.kb);
    final base =
        ledger.document(document.id)?.revisionId ??
        await documents.currentRevisionId(document.id);
    // A never-synced local document needs no remote action.
    if (base == null) return;

    final receipt = await documents.publishDeletion(
      kbId: session.kb.manifest.kbId,
      documentId: document.id,
      relativePath: relativePath,
      expectedCurrentRevisionId: base,
    );
    if (receipt.wasPublished) {
      await ledger.remove(document.id);
      _ref
          .read(differencesControllerProvider.notifier)
          .markPublished(document.id);
    } else {
      _ref
          .read(differencesControllerProvider.notifier)
          .markProposed(document.id, receipt.id);
    }
  }

  /// Pulls canonical revisions without overwriting local work. A file is only
  /// replaced when it still has the hash recorded at the previous sync point;
  /// divergent files are reported as conflicts and left byte-for-byte intact.
  Future<SyncPullResult> pullRemoteChanges() async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }
    final role = await _ref.read(kbRoleProvider.future);
    if (role == KbRole.local) {
      throw const SyncException('This Knowledge Base is not shared.');
    }
    if (role == KbRole.invited) {
      throw const SyncException('Accept the invitation first.');
    }

    await _ref.read(documentControllerProvider.notifier).flush();
    final kb = session.kb;
    final ledger = await SyncLedger.open(kb);
    final snapshots = await _ref
        .read(documentRepositoryProvider)
        .snapshot(kb.manifest.kbId);
    final remoteIds = snapshots.map((item) => item.document.id).toSet();
    var updated = 0;
    var conflicts = 0;
    var recovered = 0;
    final conflictIds = <String>{};

    for (final snapshot in snapshots) {
      final previous = ledger.document(snapshot.document.id);
      final target = File(kb.absolutePathFor(snapshot.path));
      if (previous?.revisionId == snapshot.revisionId &&
          previous?.path == snapshot.path &&
          await target.exists()) {
        if (previous?.protection != snapshot.protection) {
          final local = await kb.readDocument(snapshot.path);
          await ledger.record(
            document: local,
            revisionId: snapshot.revisionId,
            path: snapshot.path,
            protection: snapshot.protection,
          );
        }
        continue;
      }

      final oldPath = previous?.path ?? snapshot.path;
      final oldFile = File(kb.absolutePathFor(oldPath));
      if (previous == null) {
        if (await target.exists()) {
          conflicts++;
          conflictIds.add(snapshot.document.id);
          continue;
        }
      } else if (await oldFile.exists()) {
        try {
          final local = await kb.readDocument(oldPath);
          if (local.contentHash != previous.contentHash) {
            conflicts++;
            conflictIds.add(snapshot.document.id);
            continue;
          }
        } on Object {
          conflicts++;
          conflictIds.add(snapshot.document.id);
          continue;
        }
        if (oldPath != snapshot.path && await target.exists()) {
          conflicts++;
          conflictIds.add(snapshot.document.id);
          continue;
        }
      }

      await _ref
          .read(assetRepositoryProvider)
          .downloadMissing(kb: kb, document: snapshot.document);
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
      final localFile = File(kb.absolutePathFor(entry.value.path));
      if (!await localFile.exists()) {
        await ledger.remove(entry.key);
        continue;
      }
      try {
        final local = await kb.readDocument(entry.value.path);
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
}

enum SyncOutcome { committed, proposed, unchanged }

class PublishConflict implements Exception {
  const PublishConflict({
    required this.documentId,
    required this.base,
    required this.canonical,
    required this.canonicalRevisionId,
    required this.canonicalPath,
    required this.protection,
    required this.local,
    required this.localPath,
    required this.merged,
    required this.pathConflict,
  });

  final String documentId;
  final BlockDocument base;
  final BlockDocument canonical;
  final String canonicalRevisionId;
  final String canonicalPath;
  final DocumentProtection? protection;
  final BlockDocument local;
  final String localPath;
  final BlockDocument merged;
  final bool pathConflict;

  @override
  String toString() =>
      'Canonical and local edits overlap. Your local copy was kept.';
}

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

final sharingControllerProvider = Provider((ref) => SharingController(ref));
