/// Deciding whether an incoming CRDT update is allowed to touch canonical
/// state.
///
/// A Yjs update is opaque and atomic: you cannot read what it does without
/// applying it, and you cannot apply half of it. So the only way to know
/// whether a peer's update writes a file they may not write is to apply it to
/// a throwaway copy, ask which files changed, and then decide — which is what
/// `workspaceStageApply` exists for.
///
/// **This runs on receive, on every update, regardless of what the server
/// already checked.** The server enforces the same rules independently, and
/// that is the enforcement that counts; this is the half that still works when
/// the server's view and the document's view disagree, and the only half that
/// would work at all if payloads were ever encrypted end to end.
///
/// The decision is all-or-nothing by necessity. An update that touches one
/// protected file the sender may not write is refused entirely, even if it
/// also contains legitimate edits to ten other files — there is no way to
/// apply the good part. That is why the sending client routes protected edits
/// into proposals *before* broadcasting: so this case is a defence against
/// misbehaviour rather than a thing that happens during ordinary work.
library;

import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';

enum CrdtVerdict {
  /// Nothing protected was touched, or the sender outranks what was.
  allowed,

  /// The sender may not write at least one file this update changes.
  refusedProtected,

  /// The sender is not a member, or holds a role that cannot edit at all.
  refusedRole,

  /// The update could not be applied even to a throwaway copy. Malformed, or
  /// for a document this workspace does not share.
  refusedMalformed,
}

class CrdtDecision {
  const CrdtDecision(this.verdict, {this.touchedFileIds = const [], this.offendingFileId, this.detail});

  final CrdtVerdict verdict;

  /// What the update would change. Empty when it could not be staged.
  final List<String> touchedFileIds;

  /// The first file that caused a refusal, for the log and the message. One is
  /// enough to explain the decision; listing all of them tells a prober which
  /// files are protected.
  final String? offendingFileId;

  final String? detail;

  bool get isAllowed => verdict == CrdtVerdict.allowed;
}

class CrdtAuthorizationGate {
  const CrdtAuthorizationGate({required this.store, required this.policy});

  final WorkspaceStore store;

  /// Null when the Knowledge Base has no signed policy — which means no file
  /// is protected, not that everything is permitted. Membership is still
  /// required, and the server still enforces its own rules.
  final WorkspacePolicy? policy;

  /// Inspects [update] without changing canonical state, and decides.
  ///
  /// [senderId] is the authenticated user id Realtime attributed the message
  /// to, not a value the sender put in the payload.
  Future<CrdtDecision> inspect({
    required String senderId,
    required List<int> update,
  }) async {
    final List<String> touched;
    try {
      touched = await store.stageApplyUpdate(update);
    } on Object catch (error) {
      return CrdtDecision(
        CrdtVerdict.refusedMalformed,
        detail: '$error',
      );
    }

    final current = policy;
    if (current == null) {
      // No policy means nothing is protected. The server is still the one
      // deciding whether this peer may write at all.
      return CrdtDecision(CrdtVerdict.allowed, touchedFileIds: touched);
    }

    final role = current.roleOf(senderId);
    if (role == null || !role.meets(PolicyRole.editor)) {
      return CrdtDecision(
        CrdtVerdict.refusedRole,
        touchedFileIds: touched,
        detail: role == null
            ? 'sender is not in the policy'
            : 'role ${role.wire} cannot edit',
      );
    }

    for (final fileId in touched) {
      if (!current.canWriteDirectly(userId: senderId, fileId: fileId)) {
        final required = current.protectedFiles[fileId]?.minimumPublishRole;
        return CrdtDecision(
          CrdtVerdict.refusedProtected,
          touchedFileIds: touched,
          offendingFileId: fileId,
          detail: required == null
              ? 'file is protected'
              : 'file requires ${required.wire}, sender is ${role.wire}',
        );
      }
    }

    return CrdtDecision(CrdtVerdict.allowed, touchedFileIds: touched);
  }

  /// Whether *this* peer should broadcast an edit to [fileId] directly, or
  /// route it into a proposal.
  ///
  /// The mirror of [inspect], asked before sending rather than on receipt.
  /// Getting this right is what keeps proposals the normal path for protected
  /// content instead of a rejection everybody sees.
  bool mustProposeInsteadOfBroadcast({
    required String userId,
    required String fileId,
  }) {
    final current = policy;
    if (current == null) return false;
    return !current.canWriteDirectly(userId: userId, fileId: fileId);
  }
}
