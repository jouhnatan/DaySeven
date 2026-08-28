/// Turns the CRDT stack on for the open Knowledge Base.
///
/// This is the one place that knows how the pieces fit: a [WorkspaceStore]
/// holding the yrs document, a verified [WorkspacePolicy] saying who may write
/// what, a [CrdtAuthorizationGate] built from the two, and a [CrdtSession]
/// driving the transport. Everything below this file is deliberately ignorant
/// of Riverpod, the filesystem watcher, and each other.
///
/// The local folder and `workspace.bin` are authoritative. The Render relay is
/// deliberately ephemeral: it only carries binary updates between currently
/// connected members, while a device-local SQLite journal retains work that
/// still needs to be sent or reviewed.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart' show User;

import 'package:dayseven/app/security_log.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/app/workspace/open_document.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/blocks/blocks.dart';
import 'package:dayseven/shared/blocks/markdown.dart';
import 'package:dayseven/shared/crdt/awareness.dart';
import 'package:dayseven/shared/crdt/collaboration_journal.dart';
import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/generated/api/workspace.dart'
    as workspace_api;
import 'package:dayseven/shared/crdt/crdt_session.dart';
import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/policy_source.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/security/security_log.dart';

const String kPolicyFileName = 'policy.json';

class CrdtProposalReview {
  const CrdtProposalReview({
    required this.proposal,
    required this.base,
    required this.proposed,
    required this.current,
    required this.relativePath,
  });

  final CollaborationProposal proposal;
  final BlockDocument base;
  final BlockDocument proposed;
  final BlockDocument current;
  final String relativePath;
}

/// Everything running for one open Knowledge Base, or the reason nothing is.
class CrdtCollaboration {
  const CrdtCollaboration({
    this.store,
    this.session,
    this.awareness,
    this.policy,
    this.unavailable,
    this.linkState = const CrdtLinkState(),
    this.lastRefusal,
    this.refusalCount = 0,
  });

  final WorkspaceStore? store;
  final CrdtSession? session;
  final AwarenessResolver? awareness;
  final WorkspacePolicy? policy;

  /// Why collaboration is not running, in a sentence fit to show someone.
  /// Null when it is running, and also null when it was simply never asked
  /// for — [isActive] is the question to ask, not this.
  final String? unavailable;

  final CrdtLinkState linkState;
  final CrdtDecision? lastRefusal;
  final int refusalCount;

  bool get isActive => session != null;

  CrdtCollaboration copyWith({
    CrdtLinkState? linkState,
    CrdtDecision? Function()? lastRefusal,
    int? refusalCount,
  }) => CrdtCollaboration(
    store: store,
    session: session,
    awareness: awareness,
    policy: policy,
    unavailable: unavailable,
    linkState: linkState ?? this.linkState,
    lastRefusal: lastRefusal == null ? this.lastRefusal : lastRefusal(),
    refusalCount: refusalCount ?? this.refusalCount,
  );

  static const CrdtCollaboration off = CrdtCollaboration();
}

final crdtCollaborationProvider =
    StateNotifierProvider<CrdtCollaborationController, CrdtCollaboration>(
      CrdtCollaborationController.new,
    );

class CrdtCollaborationController extends StateNotifier<CrdtCollaboration> {
  CrdtCollaborationController(this._ref) : super(CrdtCollaboration.off) {
    _ref.listen(kbSessionProvider, (_, next) => unawaited(_bind(next)));
    _ref.listen(currentUserProvider, (_, _) {
      unawaited(_bind(_ref.read(kbSessionProvider)));
    });
    _ref.listen<OpenDocument?>(documentControllerProvider, _documentChanged);
  }

  final Ref _ref;

  StreamSubscription<List<String>>? _remoteChanges;
  StreamSubscription<CrdtLinkState>? _linkStates;
  StreamSubscription<CrdtDecision>? _refusals;
  String? _boundKbId;
  SecurityLog? _log;

  /// Rebuilds the live room and reconciles the open Knowledge Base.
  Future<void> refresh() => _bind(_ref.read(kbSessionProvider), force: true);

  /// Rebuilds the whole stack for whatever Knowledge Base is now open.
  Future<void> _bind(KbSession? session, {bool force = false}) async {
    final kb = session?.kb;
    if (kb == null) {
      await _teardown();
      return;
    }
    if (!force && _boundKbId == kb.manifest.kbId && _last.isActive) return;
    await _teardown();

    if (!isSupabaseConfigured) {
      _publish(
        const CrdtCollaboration(
          unavailable:
              'This build has no Supabase credentials, so collaboration '
              'is unavailable. The Knowledge Base still works locally.',
        ),
      );
      return;
    }
    final user = _ref.read(currentUserProvider);
    if (user == null) {
      _publish(
        const CrdtCollaboration(
          unavailable: 'Sign in to collaborate. Local editing is unaffected.',
        ),
      );
      return;
    }

    try {
      final profile = await _profileForPolicy(user);
      await _start(kb: kb, userId: user.id, username: profile.username);
    } on Object catch (error) {
      // Every failure here is survivable. The Knowledge Base is a folder of
      // Markdown and it keeps working.
      await _teardown();
      _publish(CrdtCollaboration(unavailable: describeError(error)));
    }
  }

  Future<void> _start({
    required KnowledgeBase kb,
    required String userId,
    required String username,
  }) async {
    final kbId = kb.manifest.kbId;
    final repository = CrdtSyncRepository(supabase);
    final prepared = await _preparePolicy(
      kb: kb,
      kbId: kbId,
      repository: repository,
    );
    final workspace = await WorkspaceStore.openFor(
      kb,
      preserveCanonicalFileIds:
          prepared.policy?.protectedFiles.keys.toSet() ?? const {},
    );
    final journal = await CollaborationJournal.open(rootPath: kb.rootPath);
    final transport = CrdtSyncService(
      roomId: kbId,
      accessTokenProvider: () async {
        final accessToken = supabase.auth.currentSession?.accessToken;
        if (accessToken == null || accessToken.isEmpty) {
          throw StateError('Sign in to collaborate.');
        }
        return accessToken;
      },
    );

    final log = await _openSecurityLog();
    final session = CrdtSession(
      kbId: kbId,
      store: workspace,
      authorId: userId,
      gate: CrdtAuthorizationGate(store: workspace, policy: prepared.policy),
      transport: transport,
      journal: journal,
      securityLog: log,
    );

    // Remote changes become Markdown on disk. The watcher suppression inside
    // WorkspaceStore is what stops that write from being read back in as an
    // external edit and pushed out again.
    _remoteChanges = session.remoteChanges.listen((fileIds) async {
      for (final fileId in fileIds) {
        try {
          await workspace.materializeFile(fileId);
        } on Object {
          // One unwritable file must not stop the rest arriving.
        }
      }
      if (fileIds.isNotEmpty) {
        await _ref.read(kbControllerProvider.notifier).refreshTree();
      }
    });
    _linkStates = session.states.listen((linkState) {
      if (!identical(_last.session, session)) return;
      _publish(_last.copyWith(linkState: linkState));
    });
    _refusals = session.refusals.listen((decision) {
      if (!identical(_last.session, session)) return;
      _publish(
        _last.copyWith(
          lastRefusal: () => decision,
          refusalCount: _last.refusalCount + 1,
        ),
      );
    });

    _boundKbId = kbId;
    _log = log;
    _publish(
      CrdtCollaboration(
        store: workspace,
        session: session,
        awareness: AwarenessResolver(workspace),
        policy: prepared.policy,
        linkState: session.state,
      ),
    );

    await session.start();
  }

  Future<Profile> _profileForPolicy(User user) async {
    try {
      final profile = await _ref.read(myProfileProvider.future);
      if (profile != null) return profile;
    } on Object {
      // Auth metadata is the immediate fallback used elsewhere in the app.
    }
    final metadata = user.userMetadata ?? const <String, Object?>{};
    final username = metadata['username'];
    if (username is! String || usernameProblem(username) != null) {
      throw const WorkspacePolicyException(
        'Your immutable username could not be loaded, so this device cannot '
        'open policy signing safely.',
      );
    }
    return Profile(id: user.id, username: username, displayName: username);
  }

  /// The protection rules to run with.
  ///
  /// Postgres is the authority and row level security already limits every row
  /// to members, so reading it with this user's own credentials is what makes
  /// the answer trustworthy. The cache exists only for a member who cannot
  /// reach it, and [resolvePolicySource] decides between them.
  Future<_PreparedPolicy> _preparePolicy({
    required KnowledgeBase kb,
    required String kbId,
    required CrdtSyncRepository repository,
  }) async {
    final policyFile = _policyFile(kb);

    WorkspacePolicy? authoritative;
    String? authorityError;
    try {
      authoritative = await repository.policySnapshot(kbId);
    } on Object catch (error) {
      authorityError = describeError(error);
    }

    final source = resolvePolicySource(
      authoritative: authoritative,
      cachedDocument: await policyFile.exists()
          ? await policyFile.readAsString()
          : null,
      expectedKbId: kbId,
      authorityError: authorityError,
    );

    switch (source) {
      case PolicyFromAuthority(:final policy, :final documentToCache):
        try {
          await _writePolicyDocument(policyFile, documentToCache);
        } on Object {
          // An unwritable metadata directory only costs the offline copy.
        }
        return _PreparedPolicy(policy: policy);

      case PolicyFromCache(:final policy):
        return _PreparedPolicy(policy: policy);

      case PolicyUnavailable(:final message):
        throw WorkspacePolicyException(message);
    }
  }

  File _policyFile(KnowledgeBase kb) => File(
    p.join(kb.rootPath, kMetadataDirName, kYjsSubdirName, kPolicyFileName),
  );

  Future<void> _writePolicyDocument(File file, String document) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(document, flush: true);
    await temporary.rename(file.path);
  }

  /// The installation's log, shared with sign-in and membership changes, so
  /// the whole trail is one file in one order.
  Future<SecurityLog> _openSecurityLog() =>
      _ref.read(securityLogProvider.future);

  void _documentChanged(OpenDocument? previous, OpenDocument? next) {
    // DocumentController flips dirty to false only after the Markdown write
    // finishes. Observing that edge keeps disk strictly ahead of CRDT state.
    if (previous?.dirty != true || next == null || next.dirty) return;
    if (previous!.document.id != next.document.id) return;
    unawaited(_ingestPersistedDocument(next));
  }

  Future<void> _ingestPersistedDocument(OpenDocument document) async {
    final collaboration = _last;
    final session = collaboration.session;
    final workspace = collaboration.store;
    final user = _ref.read(currentUserProvider);
    final kb = _ref.read(kbSessionProvider)?.kb;
    if (session == null || workspace == null || user == null || kb == null) {
      return;
    }
    if (_boundKbId != kb.manifest.kbId) return;

    final gate = CrdtAuthorizationGate(
      store: workspace,
      policy: collaboration.policy,
    );
    if (gate.mustProposeInsteadOfBroadcast(
      userId: user.id,
      fileId: document.document.id,
    )) {
      // The Markdown working copy remains on disk. It enters canonical Yjs
      // state only if the person explicitly proposes it and a reviewer
      // approves it through Differences.
      return;
    }

    await workspace.upsertFile(
      fileId: document.document.id,
      path: document.relativePath,
      protected:
          collaboration.policy?.isProtected(document.document.id) ?? false,
    );
    await workspace.setFileText(
      fileId: document.document.id,
      next: encodeMarkdown(document.document),
    );
    session.noteLocalChange();
  }

  /// Call after a local edit to [fileId] that this device is allowed to make.
  ///
  /// Returns false when the edit must be proposed instead — the caller should
  /// route it through [propose] rather than saving it as canonical.
  bool noteLocalEdit({required String fileId, required String userId}) {
    final current = state;
    final session = current.session;
    if (session == null) return true;
    final mustPropose = CrdtAuthorizationGate(
      store: current.store!,
      policy: current.policy,
    ).mustProposeInsteadOfBroadcast(userId: userId, fileId: fileId);
    if (mustPropose) return false;
    session.noteLocalChange();
    return true;
  }

  Future<String?> propose({
    required String fileId,
    required String text,
  }) async {
    final session = state.session;
    if (session == null) return null;
    return session.proposeChange(fileId: fileId, text: text);
  }

  Future<void> reconcile() async {
    final session = _last.session;
    if (session == null) return;
    await session.reconcile();
  }

  Future<List<CrdtProposalReview>> pendingProposalReviews() async {
    final session = _last.session;
    final workspace = _last.store;
    if (session == null || workspace == null) return const [];
    final proposals = session.journal.proposals(
      status: CollaborationProposalStatus.pending,
    );
    final reviews = <CrdtProposalReview>[];
    for (final proposal in proposals) {
      reviews.add(await _decodeProposal(workspace, proposal));
    }
    return reviews;
  }

  Future<CrdtProposalReview> _decodeProposal(
    WorkspaceStore workspace,
    CollaborationProposal proposal,
  ) async {
    final handle = await workspace_api.workspaceLoad(
      bytes: proposal.baseSnapshot,
    );
    try {
      final baseText = await workspace_api.fileText(
        handle: handle,
        fileId: proposal.fileId,
      );
      await workspace_api.workspaceApply(
        handle: handle,
        update: proposal.update,
      );
      final proposedText = await workspace_api.fileText(
        handle: handle,
        fileId: proposal.fileId,
      );
      final meta = await workspace.getFileMeta(proposal.fileId);
      return CrdtProposalReview(
        proposal: proposal,
        base: decodeMarkdown(baseText),
        proposed: decodeMarkdown(proposedText),
        current: decodeMarkdown(await workspace.getFileText(proposal.fileId)),
        relativePath: meta.path,
      );
    } finally {
      await workspace_api.workspaceClose(handle: handle);
    }
  }

  Future<CollaborationResolution> resolveProposal({
    required String proposalId,
    required bool approve,
    BlockDocument? merged,
    String? reviewNote,
  }) async {
    final session = _last.session;
    final workspace = _last.store;
    if (session == null || workspace == null) {
      throw StateError('Collaboration is not active.');
    }
    List<int>? resolvedUpdate;
    if (approve) {
      if (merged == null) throw ArgumentError.notNull('merged');
      final branch = await workspace.branch();
      try {
        await branch.setFileText(
          fileId: merged.id,
          next: encodeMarkdown(merged),
        );
        resolvedUpdate = await branch.diffSinceBase();
      } finally {
        await branch.close();
      }
    }
    return session.resolveProposal(
      proposalId: proposalId,
      approve: approve,
      reviewNote: reviewNote,
      resolvedUpdate: resolvedUpdate,
    );
  }

  /// Stops everything and releases the Rust handle.
  ///
  /// The `mounted` checks are not ceremony. A test — or a closing window — can
  /// dispose the container before this finishes, and the session and store
  /// must still be torn down: a leaked handle leaks a whole document.
  Future<void> _teardown() async {
    await _remoteChanges?.cancel();
    _remoteChanges = null;
    await _linkStates?.cancel();
    _linkStates = null;
    await _refusals?.cancel();
    _refusals = null;
    _boundKbId = null;
    _log?.flush();
    _log = null;
    final previous = _last;
    _last = CrdtCollaboration.off;
    if (mounted) state = CrdtCollaboration.off;
    await previous.session?.dispose();
    await previous.store?.close();
  }

  /// Mirrors [state] so teardown can still find what to close after the
  /// notifier has been disposed and `state` can no longer be read.
  CrdtCollaboration _last = CrdtCollaboration.off;

  void _publish(CrdtCollaboration next) {
    _last = next;
    if (mounted) state = next;
  }

  @override
  void dispose() {
    unawaited(_teardown());
    super.dispose();
  }
}

class _PreparedPolicy {
  const _PreparedPolicy({required this.policy});

  final WorkspacePolicy? policy;
}
