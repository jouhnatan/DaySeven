/// Turns the CRDT stack on for the open Knowledge Base.
///
/// This is the one place that knows how the pieces fit: a [WorkspaceStore]
/// holding the yrs document, a verified [WorkspacePolicy] saying who may write
/// what, a [CrdtAuthorizationGate] built from the two, and a [CrdtSession]
/// driving the transport. Everything below this file is deliberately ignorant
/// of Riverpod, the filesystem watcher, and each other.
///
/// **Off by default.** The reviewed-edit path through `documents`/`revisions`
/// is what the two people running this app rely on, and it stays authoritative
/// until CRDT sync has been proven end to end between two real clients. This
/// controller only starts when `AppStore.crdtCollaboration` is switched on, and
/// every failure inside it degrades to "collaboration unavailable" rather than
/// taking the Knowledge Base down — a folder of Markdown files must keep
/// working when the network, the native library, or the policy does not.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:dayseven/app/app_store.dart';
import 'package:dayseven/app/workspace/kb_session.dart';
import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:dayseven/shared/crdt/awareness.dart';
import 'package:dayseven/shared/crdt/crdt_authorization.dart';
import 'package:dayseven/shared/crdt/crdt_session.dart';
import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:dayseven/shared/crdt/workspace_store.dart';
import 'package:dayseven/shared/kb/bundle.dart';
import 'package:dayseven/shared/security/security_log.dart';

const String kPolicyFileName = 'policy.json';

/// Everything running for one open Knowledge Base, or the reason nothing is.
class CrdtCollaboration {
  const CrdtCollaboration({
    this.store,
    this.session,
    this.awareness,
    this.policy,
    this.unavailable,
  });

  final WorkspaceStore? store;
  final CrdtSession? session;
  final AwarenessResolver? awareness;
  final WorkspacePolicy? policy;

  /// Why collaboration is not running, in a sentence fit to show someone.
  /// Null when it is running, and also null when it was simply never asked
  /// for — [isActive] is the question to ask, not this.
  final String? unavailable;

  bool get isActive => session != null;

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
  }

  final Ref _ref;

  StreamSubscription<List<String>>? _remoteChanges;
  String? _boundKbId;
  SecurityLog? _log;

  /// Rebuilds the whole stack for whatever Knowledge Base is now open.
  Future<void> _bind(KbSession? session) async {
    final kb = session?.kb;
    if (kb == null) {
      await _teardown();
      return;
    }
    if (_boundKbId == kb.manifest.kbId && _last.isActive) return;
    await _teardown();

    final store = await _ref.read(appStoreProvider.future);
    if (!await store.developerFlag(AppStore.crdtCollaboration)) {
      // Not an error, and not worth a message: nobody asked for it.
      _publish(CrdtCollaboration.off);
      return;
    }
    if (!isSupabaseConfigured) {
      _publish(const CrdtCollaboration(
        unavailable: 'This build has no Supabase credentials, so collaboration '
            'is unavailable. The Knowledge Base still works locally.',
      ));
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
      await _start(kb: kb, userId: user.id);
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
  }) async {
    final kbId = kb.manifest.kbId;
    final repository = CrdtSyncRepository(supabase);
    final workspace = await WorkspaceStore.openFor(kb);

    final policy = await _loadPolicy(
      kb: kb,
      kbId: kbId,
      repository: repository,
    );

    final log = await _openSecurityLog();
    final session = CrdtSession(
      kbId: kbId,
      store: workspace,
      repository: repository,
      authorId: userId,
      gate: CrdtAuthorizationGate(store: workspace, policy: policy),
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

    _boundKbId = kbId;
    _log = log;
    _publish(
      CrdtCollaboration(
        store: workspace,
        session: session,
        awareness: AwarenessResolver(workspace),
        policy: policy,
      ),
    );

    await session.start();
  }

  /// Reads and verifies `metadata/yjs/policy.json`.
  ///
  /// A missing policy and an unverifiable one are different things and are
  /// handled differently on purpose. Missing means a Knowledge Base with
  /// nothing protected, which is ordinary. Unverifiable means somebody changed
  /// the file, and that must stop collaboration rather than quietly proceed
  /// with no protections — so it is rethrown.
  Future<WorkspacePolicy?> _loadPolicy({
    required KnowledgeBase kb,
    required String kbId,
    required CrdtSyncRepository repository,
  }) async {
    final file = File(
      p.join(kb.rootPath, kMetadataDirName, kYjsSubdirName, kPolicyFileName),
    );
    if (!await file.exists()) return null;

    final publicKey = await repository.policyPublicKey(kbId);
    if (publicKey == null) {
      throw const WorkspacePolicyException(
        'This Knowledge Base has a policy file but no published signing key, '
        'so its permissions cannot be verified. Ask the owner to republish the '
        'policy.',
      );
    }
    return WorkspacePolicy.verified(
      await file.readAsString(),
      ownerPublicKey: publicKey,
      expectedKbId: kbId,
    );
  }

  Future<SecurityLog> _openSecurityLog() async {
    try {
      final dir = await getApplicationSupportDirectory();
      return SecurityLog(
        sink: SecurityLogFileSink(File(p.join(dir.path, 'security.log'))),
      );
    } on Object {
      // Nowhere to write is not a reason to refuse to collaborate.
      return SecurityLog(sink: const NullSecuritySink());
    }
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

  /// Stops everything and releases the Rust handle.
  ///
  /// The `mounted` checks are not ceremony. A test — or a closing window — can
  /// dispose the container before this finishes, and the session and store
  /// must still be torn down: a leaked handle leaks a whole document.
  Future<void> _teardown() async {
    await _remoteChanges?.cancel();
    _remoteChanges = null;
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
