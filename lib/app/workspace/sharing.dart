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
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/document_repository.dart';
import 'package:dayseven/shared/backend/asset_repository.dart';
import 'package:dayseven/features/knowledge_base/data/kb_repository.dart';
import 'package:dayseven/features/review/data/change_set_repository.dart';
import 'package:dayseven/features/review/data/proposals.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/app/workspace/sync_ledger.dart';

enum KbRole {
  /// Not signed in, or this Knowledge Base was never shared.
  local,

  /// Signed in and the owner: saves commit revisions.
  owner,

  /// Owner-appointed manager: edits, syncs, reviews and manages non-owners.
  coOwner,

  /// Signed in and a member: saves are proposed for review.
  editor,

  /// Read-only collaborator who can approve and reject proposals.
  reviewer,

  /// Invited but not yet accepted.
  invited,
}

/// This account's standing in the Knowledge Base that is currently open.
final kbRoleProvider = FutureProvider<KbRole>((ref) async {
  final session = ref.watch(kbSessionProvider);
  final user = ref.watch(currentUserProvider);
  if (session == null || user == null || !isSupabaseConfigured) {
    return KbRole.local;
  }

  try {
    final row = await supabase
        .from('kb_members')
        .select('role, accepted_at')
        .eq('kb_id', session.kb.manifest.kbId)
        .eq('user_id', user.id)
        .maybeSingle();

    if (row == null) return KbRole.local;
    if (row['accepted_at'] == null) return KbRole.invited;
    return switch (row['role']) {
      'owner' => KbRole.owner,
      'co_owner' => KbRole.coOwner,
      'reviewer' => KbRole.reviewer,
      _ => KbRole.editor,
    };
  } on PostgrestException {
    return KbRole.local;
  }
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
    _ref.invalidate(pendingProposalsProvider);
    _ref.invalidate(kbRoleProvider);
  }

  /// Sends the open document upstream: a commit if this account owns the
  /// Knowledge Base, a proposal if it does not.
  ///
  /// Returns what happened, for the interface to report.
  Future<SyncOutcome> syncOpenDocument() async {
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
    final documents = _ref.read(documentRepositoryProvider);
    final kbId = session.kb.manifest.kbId;

    switch (role) {
      case KbRole.local:
        throw const SyncException(
          'Share this Knowledge Base before syncing documents.',
        );
      case KbRole.invited:
        throw const SyncException('Accept the invitation first.');

      case KbRole.owner:
      case KbRole.coOwner:
        await _ref
            .read(assetRepositoryProvider)
            .uploadReferenced(kb: session.kb, document: document);
        final existing = await documents.currentRevisionId(document.id);
        if (existing == null) {
          final revisionId = await documents.publish(
            kbId: kbId,
            relativePath: relativePath,
            document: document,
          );
          final ledger = await SyncLedger.open(session.kb);
          await ledger.record(
            document: document,
            revisionId: revisionId,
            path: relativePath,
          );
        } else {
          final revisionId = await documents.commit(
            kbId: kbId,
            relativePath: relativePath,
            document: document,
          );
          final ledger = await SyncLedger.open(session.kb);
          await ledger.record(
            document: document,
            revisionId: revisionId,
            path: relativePath,
          );
        }
        return SyncOutcome.committed;

      case KbRole.editor:
        await _ref
            .read(assetRepositoryProvider)
            .uploadReferenced(kb: session.kb, document: document);
        final ledger = await SyncLedger.open(session.kb);
        final synced = ledger.document(document.id);
        final base =
            synced?.revisionId ??
            await documents.currentRevisionId(document.id);
        if (base == null) {
          await _ref
              .read(changeSetRepositoryProvider)
              .proposeCreate(
                kbId: kbId,
                relativePath: relativePath,
                content: document,
              );
          return SyncOutcome.proposed;
        }
        await _ref
            .read(changeSetRepositoryProvider)
            .propose(
              kbId: kbId,
              documentId: document.id,
              baseRevisionId: base,
              relativePath: synced != null && synced.path != relativePath
                  ? relativePath
                  : null,
              content: document,
            );
        return SyncOutcome.proposed;
      case KbRole.reviewer:
        throw const SyncException('Reviewers cannot edit documents.');
    }
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

    if (role == KbRole.owner || role == KbRole.coOwner) {
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
      if (previous?.revisionId == snapshot.revisionId &&
          previous?.path == snapshot.path) {
        continue;
      }

      final oldPath = previous?.path ?? snapshot.path;
      final oldFile = File(kb.absolutePathFor(oldPath));
      final target = File(kb.absolutePathFor(snapshot.path));
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

final sharingControllerProvider = Provider((ref) => SharingController(ref));
