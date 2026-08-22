/// Sharing a Knowledge Base, and the difference between committing a change
/// and proposing one.
///
/// The owner of a Knowledge Base writes revisions directly. Everyone else
/// proposes: their edit becomes a pending change_set for the owner to review,
/// and their own local file is theirs to keep editing meanwhile.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
export 'package:dayseven/app/workspace/kb_role.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/kb_role.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/features/knowledge_base/data/kb_repository.dart';
import 'package:dayseven/features/differences/application/differences_controller.dart';
import 'package:dayseven/features/differences/data/change_set_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';

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
    if (role != KbRole.owner && role != KbRole.coOwner) {
      throw const SyncException(
        'Only an Owner or Co-Owner can publish local changes.',
      );
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
      final revisionId = snapshot == null
          ? await documents.publish(
              kbId: kbId,
              relativePath: path,
              document: document,
            )
          : await documents.commit(
              kbId: kbId,
              relativePath: path,
              document: document,
            );
      await ledger.record(
        document: document,
        revisionId: revisionId,
        path: path,
      );
      published++;
    }

    return SyncPushResult(
      published: published,
      unchanged: unchanged,
      conflicts: conflicts,
    );
  }

  /// Explicitly publishes the open document as canonical content.
  ///
  /// Co-Owners normally submit reviewed edits automatically; this method is
  /// the deliberate escape hatch they share with Owners.
  Future<SyncOutcome> publishOpenDocumentDirectly() async {
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

    if (role != KbRole.owner && role != KbRole.coOwner) {
      throw const SyncException(
        'Only an Owner or Co-Owner can publish directly.',
      );
    }

    final documents = _ref.read(documentRepositoryProvider);
    final ledger = await SyncLedger.open(session.kb);
    final synced = ledger.document(document.id);
    final existing = await documents.currentRevisionId(document.id);
    if (existing != null && (synced == null || synced.revisionId != existing)) {
      throw const SyncException(
        'The canonical document changed. Sync latest before publishing directly.',
      );
    }

    final differences = _ref.read(differencesControllerProvider.notifier);
    await differences.prepareDirectPublish(document.id);

    await _ref
        .read(assetRepositoryProvider)
        .uploadReferenced(kb: session.kb, document: document);
    final revisionId = await documents.publishDirect(
      kbId: kbId,
      relativePath: relativePath,
      document: document,
      expectedCurrentRevisionId: existing,
    );
    await ledger.record(
      document: document,
      revisionId: revisionId,
      path: relativePath,
    );
    differences.markDirectPublished(document.id);
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

    if (role == KbRole.owner) {
      await documents.softDelete(document.id);
      await ledger.remove(document.id);
      return;
    }
    await _ref
        .read(changeSetRepositoryProvider)
        .proposeDelete(
          kbId: session.kb.manifest.kbId,
          documentId: document.id,
          baseRevisionId: base,
          relativePath: relativePath,
        );
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

    for (final snapshot in snapshots) {
      final previous = ledger.document(snapshot.document.id);
      final target = File(kb.absolutePathFor(snapshot.path));
      if (previous?.revisionId == snapshot.revisionId &&
          previous?.path == snapshot.path &&
          await target.exists()) {
        continue;
      }

      final oldPath = previous?.path ?? snapshot.path;
      final oldFile = File(kb.absolutePathFor(oldPath));
      if (previous == null) {
        if (await target.exists()) {
          conflicts++;
          continue;
        }
      } else if (await oldFile.exists()) {
        try {
          final local = await kb.readDocument(oldPath);
          if (local.contentHash != previous.contentHash) {
            conflicts++;
            continue;
          }
        } on Object {
          conflicts++;
          continue;
        }
        if (oldPath != snapshot.path && await target.exists()) {
          conflicts++;
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
          continue;
        }
      } on Object {
        conflicts++;
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
    return SyncPullResult(
      updated: updated,
      conflicts: conflicts,
      recoveredDeletions: recovered,
    );
  }
}

enum SyncOutcome { committed, proposed }

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
    required this.unchanged,
    required this.conflicts,
  });

  final int published;
  final int unchanged;
  final int conflicts;
}

final sharingControllerProvider = Provider((ref) => SharingController(ref));
