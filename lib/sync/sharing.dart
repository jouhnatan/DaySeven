/// Sharing a Knowledge Base, and the difference between committing a change
/// and proposing one.
///
/// The owner of a Knowledge Base writes revisions directly. Everyone else
/// proposes: their edit becomes a pending change_set for the owner to review,
/// and their own local file is theirs to keep editing meanwhile.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/app/state.dart';
import 'package:dayseven/kb/bundle.dart';
import 'package:dayseven/auth/auth_repository.dart';
import 'package:dayseven/sync/supabase.dart';

enum KbRole {
  /// Not signed in, or this Knowledge Base was never shared.
  local,

  /// Signed in and the owner: saves commit revisions.
  owner,

  /// Signed in and a member: saves are proposed for review.
  editor,

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
    return row['role'] == 'owner' ? KbRole.owner : KbRole.editor;
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
    for (final path in await _allDocumentPaths(session)) {
      final document = await session.kb.readDocument(path);
      await documents.publish(
        kbId: session.kb.manifest.kbId,
        relativePath: path,
        document: document,
      );
    }
    _ref.invalidate(kbRoleProvider);
  }

  Future<void> invite(String username) async {
    final session = _ref.read(kbSessionProvider);
    if (session == null) return;
    await _ref
        .read(kbRepositoryProvider)
        .invite(kbId: session.kb.manifest.kbId, username: username);
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
    final document =
        _ref.read(documentControllerProvider)?.document ?? open.document;

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
        final existing = await documents.currentRevisionId(document.id);
        if (existing == null) {
          await documents.publish(
            kbId: kbId,
            relativePath: open.relativePath,
            document: document,
          );
        } else {
          await documents.commit(kbId: kbId, document: document);
        }
        return SyncOutcome.committed;

      case KbRole.editor:
        final base = await documents.currentRevisionId(document.id);
        if (base == null) {
          throw const SyncException(
            'The owner has not shared this document yet.',
          );
        }
        await _ref
            .read(changeSetRepositoryProvider)
            .propose(
              kbId: kbId,
              documentId: document.id,
              baseRevisionId: base,
              content: document,
            );
        return SyncOutcome.proposed;
    }
  }

  Future<List<String>> _allDocumentPaths(KbSession session) async {
    final paths = <String>[];

    void walk(List<KbNode> nodes) {
      for (final node in nodes) {
        switch (node) {
          case KbFolder():
            walk(node.children);
          case KbFile():
            paths.add(node.relativePath);
        }
      }
    }

    walk(await session.kb.readTree());
    return paths;
  }
}

enum SyncOutcome { committed, proposed }

final sharingControllerProvider = Provider((ref) => SharingController(ref));
