/// Explicitly publishing local working copies to a shared Knowledge Base.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
export 'package:dayseven/app/workspace/kb_role.dart';

import 'package:dayseven/app/workspace/kb_hierarchy_replicator.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/app/workspace/sync_results.dart';
export 'package:dayseven/app/workspace/sync_results.dart';
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
    required this.documentId,
    required this.relativePath,
    required this.role,
    required this.protection,
    required this.willPropose,
  });

  final String documentId;
  final String relativePath;
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

typedef _ProtectedDocumentMetadata = ({
  String path,
  DocumentProtection protection,
});

/// Canonical protection metadata for every document, keyed by its local path.
///
/// One KB-scoped query supplies the complete shared state. The sync ledger is
/// retained as an offline fallback, and immutable document ids keep markers
/// attached when a protected file has been renamed locally.
final protectedDocumentsByPathProvider =
    FutureProvider<Map<String, DocumentProtection>>((ref) async {
      final session = ref.watch(kbSessionProvider);
      if (session == null) return const {};
      final repository = ref.watch(documentRepositoryProvider);
      final role = await ref.watch(kbRoleProvider.future);

      if (role != KbRole.local && role != KbRole.invited) {
        try {
          final rows = await repository.documentsIn(session.kb.manifest.kbId);
          final remote = <String, _ProtectedDocumentMetadata>{};
          for (final row in rows) {
            final protection = DocumentProtection.fromRow(row);
            if (protection == null) continue;
            remote[row['id'] as String] = (
              path: row['path'] as String,
              protection: protection,
            );
          }
          return await _resolveProtectedDocumentPaths(session, remote);
        } on Object {
          // Offline hierarchy markers fall back to the last durable ledger.
        }
      }

      final ledger = await SyncLedger.open(session.kb);
      final local = <String, _ProtectedDocumentMetadata>{};
      for (final entry in ledger.documents) {
        final protection = entry.value.protection;
        if (protection == null) continue;
        local[entry.key] = (path: entry.value.path, protection: protection);
      }
      return _resolveProtectedDocumentPaths(session, local);
    });

Future<Map<String, DocumentProtection>> _resolveProtectedDocumentPaths(
  KbSession session,
  Map<String, _ProtectedDocumentMetadata> protectedById,
) async {
  final byPath = <String, DocumentProtection>{};
  final unresolved = <String, DocumentProtection>{};
  final paths = documentPathsIn(session.tree).toList();
  final currentPaths = paths.toSet();

  for (final entry in protectedById.entries) {
    if (currentPaths.contains(entry.value.path)) {
      try {
        final document = await session.kb.readDocument(entry.value.path);
        if (document.id == entry.key) {
          byPath[entry.value.path] = entry.value.protection;
          continue;
        }
      } on Object {
        // Resolve a moved or temporarily unreadable path by document id below.
      }
    }
    unresolved[entry.key] = entry.value.protection;
  }
  if (unresolved.isEmpty) return byPath;

  for (final path in paths) {
    if (byPath.containsKey(path)) continue;
    try {
      final document = await session.kb.readDocument(path);
      final protection = unresolved.remove(document.id);
      if (protection != null) byPath[path] = protection;
      if (unresolved.isEmpty) break;
    } on Object {
      // Do not attach protection metadata that cannot be tied to a document.
    }
  }
  return byPath;
}

final openDocumentPublishActionProvider =
    FutureProvider<OpenDocumentPublishAction?>((ref) async {
      final target = ref.watch(
        documentControllerProvider.select(
          (open) => open == null
              ? null
              : (id: open.document.id, path: open.relativePath),
        ),
      );
      final role = await ref.watch(kbRoleProvider.future);
      if (target == null || role.publishingRank == null) return null;
      final protection = await ref.watch(openDocumentProtectionProvider.future);
      return OpenDocumentPublishAction(
        documentId: target.id,
        relativePath: target.path,
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
        ref.invalidate(protectedDocumentsByPathProvider);
      } on Object {
        // Manual Sync remains available and surfaces its error. A wake
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
      // interruption made the first download partial. Manual Sync can resume.
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
  ///
  /// Delegates to [KbHierarchyReplicator] so hierarchy + data replication has a
  /// single, testable implementation. Publishing still remains an explicit
  /// action – the replicator does not auto-decide for the user, it only
  /// ensures missing hierarchy/files are created when asked to sync.
  Future<SyncPushResult> pushLocalChanges() =>
      _ref.read(kbHierarchyReplicatorProvider).ensureRemoteMatchesLocal();

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
    var currentOpen = _ref.read(documentControllerProvider) ?? open;

    final role = await _ref.read(kbRoleProvider.future);
    final kbId = session.kb.manifest.kbId;

    if (role.publishingRank == null) {
      throw const SyncException('Your role cannot edit this document.');
    }

    final documents = _ref.read(documentRepositoryProvider);
    final ledger = await SyncLedger.open(session.kb);
    var current = await documents.snapshotForDocument(currentOpen.document.id);
    currentOpen = await _forkCopiedOpenDocumentIfNeeded(
      session: session,
      open: currentOpen,
      canonical: current,
    );
    final document = currentOpen.document;
    final relativePath = currentOpen.relativePath;
    if (current?.document.id != document.id) current = null;
    var synced = ledger.document(document.id);
    var workingDocument = document;
    var workingPath = relativePath;

    if (current != null && synced == null) {
      final error = const SyncException(
        'This device has no sync base for the canonical document. Sync the '
        'Knowledge Base before publishing.',
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
            'The saved merge base is unavailable. Sync the Knowledge Base '
            'before publishing.',
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

  Future<DocumentProtection?> setDocumentProtection({
    required String documentId,
    required String relativePath,
    required DocumentProtection? protection,
  }) async {
    final session = _ref.read(kbSessionProvider);
    await _ref.read(documentControllerProvider.notifier).flush();
    var open = _ref.read(documentControllerProvider);
    if (session == null || open == null) {
      throw const SyncException('Open a document first.');
    }
    if (open.document.id != documentId || open.relativePath != relativePath) {
      throw const SyncException(
        'The open document changed. Reopen protection from the document you '
        'want to protect.',
      );
    }
    final role = await _ref.read(kbRoleProvider.future);
    if (role.publishingRank == null) {
      throw const SyncException('Your role cannot protect documents.');
    }
    final documents = _ref.read(documentRepositoryProvider);
    var canonical = await documents.snapshotForDocument(open.document.id);
    open = await _forkCopiedOpenDocumentIfNeeded(
      session: session,
      open: open,
      canonical: canonical,
    );
    final currentOpen = _ref.read(documentControllerProvider);
    if (currentOpen?.document.id != open.document.id ||
        currentOpen?.relativePath != open.relativePath) {
      throw const SyncException(
        'The open document changed before protection was saved. Try again.',
      );
    }
    if (canonical?.document.id != open.document.id) canonical = null;

    // Protecting a new or copied file is one explicit operation: first give
    // that file its own canonical row, then protect that exact row.
    if (canonical == null) {
      final outcome = await publishOpenDocument();
      if (outcome == SyncOutcome.proposed) {
        throw const SyncException(
          'This document must be approved before it can be protected.',
        );
      }
      canonical = await documents.snapshotForDocument(open.document.id);
      if (canonical == null) {
        throw const SyncException(
          'The document was published but its canonical copy is unavailable.',
        );
      }
    }

    final updated = await documents.setProtection(
      kbId: session.kb.manifest.kbId,
      documentId: open.document.id,
      protection: protection,
    );
    final ledger = await SyncLedger.open(session.kb);
    // Protection changes metadata only. Preserve the actual canonical base;
    // never mark un-published local words or a local rename as synchronized.
    await ledger.record(
      document: canonical.document,
      revisionId: canonical.revisionId,
      path: canonical.path,
      protection: updated,
    );
    _ref.invalidate(openDocumentProtectionProvider);
    _ref.invalidate(openDocumentPublishActionProvider);
    _ref.invalidate(protectedDocumentsByPathProvider);
    return updated;
  }

  /// A Markdown file copied outside the app retains its embedded UUID. If the
  /// original canonical file is also present locally, publishing the copy by
  /// that UUID would update the original. Fork the copy before any remote
  /// write so its visible path and its shared identity stay aligned.
  Future<OpenDocument> _forkCopiedOpenDocumentIfNeeded({
    required KbSession session,
    required OpenDocument open,
    required RemoteDocumentSnapshot? canonical,
  }) async {
    if (canonical == null || canonical.path == open.relativePath) return open;

    final canonicalFile = File(session.kb.absolutePathFor(canonical.path));
    if (!await canonicalFile.exists()) return open;
    final localCanonical = await session.kb.readDocument(canonical.path);
    if (localCanonical.id != open.document.id) return open;

    final forked = BlockDocument(
      id: newId(),
      title: open.document.title,
      blocks: open.document.blocks,
      schemaVersion: open.document.schemaVersion,
    );
    await session.kb.writeDocument(open.relativePath, forked);
    session.index.upsert(open.relativePath, forked);
    _ref
        .read(documentControllerProvider.notifier)
        .replacePersistedDocument(
          relativePath: open.relativePath,
          previousDocumentId: open.document.id,
          document: forked,
        );
    return OpenDocument(
      relativePath: open.relativePath,
      document: forked,
      dirty: false,
    );
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
  ///
  /// Delegates to [KbHierarchyReplicator.ensureLocalMatchesRemote] – the
  /// single place that replicates missing hierarchy (e.g. `Awayside/` for
  /// `Awayside/Untitled.md`) and file data when the peer has no copy.
  Future<SyncPullResult> pullRemoteChanges() async {
    final result = await _ref
        .read(kbHierarchyReplicatorProvider)
        .ensureLocalMatchesRemote();
    _ref.invalidate(protectedDocumentsByPathProvider);
    _ref.invalidate(openDocumentProtectionProvider);
    _ref.invalidate(openDocumentPublishActionProvider);
    return result;
  }

  /// Bidirectional reconcile: first pulls missing hierarchy/data, then pushes
  /// local changes. Used by manual Sync when a
  /// full hierarchy sync is desired rather than a single-direction pull.
  Future<ReconcileResult> reconcileHierarchy() async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) {
      throw const SyncException('Open a Knowledge Base first.');
    }
    final result = await _ref
        .read(kbHierarchyReplicatorProvider)
        .reconcile(sessionOverride: session);
    _ref.invalidate(protectedDocumentsByPathProvider);
    _ref.invalidate(openDocumentProtectionProvider);
    _ref.invalidate(openDocumentPublishActionProvider);
    return result;
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



final sharingControllerProvider = Provider((ref) => SharingController(ref));
