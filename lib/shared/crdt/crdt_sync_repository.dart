/// The server side of CRDT collaboration: durable Yjs history plus the live
/// broadcast topic.
///
/// Two channels with different guarantees, and the difference matters:
///
///   * `crdt:<kbId>` Realtime Broadcast is fast and lossy. It keeps no history,
///     so anything sent while a peer is disconnected is simply gone. It exists
///     to make a collaborator's keystrokes show up now.
///   * `yjs_updates` / `yjs_snapshots` in Postgres are slow and durable. They
///     are the record a peer catches up from.
///
/// So a client must broadcast *and* persist, and must never treat having
/// broadcast as having saved. Because Yjs updates are idempotent and
/// commutative, a peer receiving the same update by both routes is harmless —
/// which is what lets the two run independently instead of in lockstep.
///
/// Persistence is debounced by the caller (see [kCrdtPushDebounce]).
/// `private.yjs_push_update` enforces a floor under that debounce server-side;
/// per-keystroke writes through PostgREST are what caused the outage this
/// architecture is replacing, and neither layer is trusted to remember alone.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/shared/crdt/workspace_policy.dart';

/// How long a client accumulates local edits before writing them to Postgres.
/// The server rejects a caller averaging faster than 2/second over 10 seconds.
const Duration kCrdtPushDebounce = Duration(seconds: 3);

/// Realtime broadcast is not debounced this far — liveness is its whole point —
/// but it is still batched, so a fast typist sends frames rather than keystrokes.
const Duration kCrdtBroadcastDebounce = Duration(milliseconds: 200);

const String kCrdtBroadcastEvent = 'yjs_update';

/// A Yjs v1 update carrying nothing encodes as two zero bytes — one varint for
/// "no structs", one for "no deletes" — not as an empty buffer. Anything
/// carrying real content is longer.
///
/// This is the check that keeps an idle client idle. Without it, every debounce
/// tick finds a "non-empty" diff, appends a two-byte row, and a workspace
/// nobody is editing still writes to Postgres forever. That write
/// amplification, not payload size, is what took the project down before.
bool isEmptyYjsUpdate(List<int> update) => update.length <= 2;

String crdtTopicFor(String kbId) => 'crdt:$kbId';

/// One Yjs update as it came off the wire, with the cursor that orders it.
class CrdtUpdate {
  const CrdtUpdate({
    required this.id,
    required this.authorId,
    required this.bytes,
  });

  /// Position in `yjs_updates`. Zero for an update that arrived by broadcast
  /// and has no durable position yet.
  final int id;
  final String authorId;
  final Uint8List bytes;

  bool get isDurable => id > 0;

  static CrdtUpdate fromRow(Map<String, Object?> row) => CrdtUpdate(
    id: (row['id'] as num?)?.toInt() ?? 0,
    authorId: row['author_id'] as String? ?? '',
    bytes: base64Decode(row['update'] as String),
  );

  Map<String, Object?> toBroadcastPayload() => {
    'author_id': authorId,
    'update': base64Encode(bytes),
  };
}

/// Everything a peer was missing at the moment it asked.
class CrdtCatchUp {
  const CrdtCatchUp({
    required this.snapshot,
    required this.snapshotThrough,
    required this.updates,
    required this.cursor,
  });

  /// A folded document state to apply *before* [updates], or null when the
  /// caller's cursor was already past the snapshot.
  final Uint8List? snapshot;
  final int? snapshotThrough;
  final List<CrdtUpdate> updates;

  /// The cursor to remember and pass to the next [CrdtSyncRepository.pull].
  final int cursor;

  bool get isEmpty => snapshot == null && updates.isEmpty;

  static CrdtCatchUp fromRpc(Map<String, Object?> value) {
    final snapshot = value['snapshot'] as String?;
    return CrdtCatchUp(
      snapshot: snapshot == null ? null : base64Decode(snapshot),
      snapshotThrough: (value['snapshot_through'] as num?)?.toInt(),
      updates: [
        for (final row in (value['updates'] as List? ?? const []))
          CrdtUpdate.fromRow(Map<String, Object?>.from(row as Map)),
      ],
      cursor: (value['cursor'] as num?)?.toInt() ?? 0,
    );
  }
}

/// A protected-file change awaiting review, as the queue lists it.
///
/// Deliberately without its payload. A review queue is a list of decisions to
/// make; downloading every pending edit to render a list of them is how a
/// quiet feature becomes an expensive one.
class CrdtProposalSummary {
  const CrdtProposalSummary({
    required this.id,
    required this.fileId,
    required this.authorId,
    required this.byteSize,
    required this.createdAt,
  });

  final String id;
  final String fileId;
  final String authorId;
  final int byteSize;
  final DateTime createdAt;

  static CrdtProposalSummary fromRow(Map<String, Object?> row) =>
      CrdtProposalSummary(
        id: row['id'] as String,
        fileId: row['file_id'] as String,
        authorId: row['author_id'] as String,
        byteSize: (row['byte_size'] as num?)?.toInt() ?? 0,
        createdAt:
            DateTime.tryParse(row['created_at'] as String? ?? '')?.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
}

/// The outcome of resolving one proposal.
///
/// [update] is present only on approval, and is the caller's to apply and
/// push. The server records the decision but cannot merge Yjs, so approving
/// and applying are two steps with the ordering enforced server-side.
class CrdtProposalOutcome {
  const CrdtProposalOutcome({
    required this.id,
    required this.fileId,
    required this.authorId,
    required this.approved,
    this.update,
  });

  final String id;
  final String fileId;
  final String authorId;
  final bool approved;
  final Uint8List? update;

  static CrdtProposalOutcome fromRpc(Map<String, Object?> value) {
    final update = value['update'] as String?;
    return CrdtProposalOutcome(
      id: value['id'] as String,
      fileId: value['file_id'] as String,
      authorId: value['author_id'] as String,
      approved: value['status'] == 'approved',
      update: update == null ? null : base64Decode(update),
    );
  }
}

class CrdtSyncRepository {
  CrdtSyncRepository(this.client);

  final SupabaseClient client;

  /// Appends one update to the durable log and returns its cursor.
  ///
  /// Throws a [PostgrestException] with code `PT429` when the caller is pushing
  /// faster than the debounce allows. That is a refusal, not a fault: back off
  /// and merge the pending updates into the next push rather than retrying,
  /// which is what `isRateLimited` in `shared/backend/supabase_client.dart` is for.
  Future<int> push({required String kbId, required List<int> update}) async {
    final value = await client.rpc(
      'yjs_push_update',
      params: {
        'p_kb_id': kbId,
        // bytea over PostgREST is hex with a leading backslash-x.
        'p_update': _toPostgresBytea(update),
      },
    );
    return (value as num).toInt();
  }

  /// Everything appended since [since], plus a snapshot when [since] is behind
  /// one. Pass null for a peer that has never synced.
  Future<CrdtCatchUp> pull({required String kbId, int? since}) async {
    final value = await client.rpc(
      'yjs_pull',
      params: {'p_kb_id': kbId, 'p_since': since},
    );
    return CrdtCatchUp.fromRpc(Map<String, Object?>.from(value as Map));
  }

  /// Replaces the log up to [through] with one folded [snapshot]. Owners and
  /// co-owners only; returns how many update rows were reclaimed.
  Future<int> compact({
    required String kbId,
    required List<int> snapshot,
    required List<int> stateVector,
    required int through,
  }) async {
    final value = await client.rpc(
      'yjs_compact',
      params: {
        'p_kb_id': kbId,
        'p_snapshot': _toPostgresBytea(snapshot),
        'p_state_vector': _toPostgresBytea(stateVector),
        'p_through': through,
      },
    );
    return (value as num).toInt();
  }

  /// Routes a change to a protected file into the review queue instead of the
  /// update log. The server re-checks the caller's role regardless of what the
  /// client decided.
  Future<String> submitProposal({
    required String kbId,
    required String fileId,
    required List<int> update,
  }) async {
    final value = await client.rpc(
      'yjs_submit_proposal',
      params: {
        'p_kb_id': kbId,
        'p_file_id': fileId,
        'p_update': _toPostgresBytea(update),
      },
    );
    return value as String;
  }

  Future<List<CrdtProposalSummary>> pendingProposals(String kbId) async {
    final value = await client.rpc(
      'yjs_pending_proposals',
      params: {'p_kb_id': kbId},
    );
    return [
      for (final row in (value as List? ?? const []))
        CrdtProposalSummary.fromRow(Map<String, Object?>.from(row as Map)),
    ];
  }

  /// Approves or rejects. On approval the returned update is this client's to
  /// apply and push; the server has only recorded the decision.
  Future<CrdtProposalOutcome> resolveProposal({
    required String proposalId,
    required bool approve,
    String? reviewNote,
  }) async {
    final value = await client.rpc(
      'yjs_resolve_proposal',
      params: {
        'p_proposal_id': proposalId,
        'p_approve': approve,
        'p_review_note': reviewNote,
      },
    );
    return CrdtProposalOutcome.fromRpc(Map<String, Object?>.from(value as Map));
  }

  /// Publishes the Ed25519 key that `policy.json` must verify against. Owners
  /// and co-owners only, enforced server-side.
  Future<void> setPolicyPublicKey({
    required String kbId,
    required List<int> publicKey,
  }) => client.rpc(
    'set_policy_public_key',
    params: {'p_kb_id': kbId, 'p_public_key': _toPostgresBytea(publicKey)},
  );

  /// The key to verify `policy.json` against, or null when the Knowledge Base
  /// has never published one.
  Future<Uint8List?> policyPublicKey(String kbId) async {
    final row = await client
        .from('knowledge_bases')
        .select('policy_public_key')
        .eq('id', kbId)
        .maybeSingle();
    final value = row?['policy_public_key'];
    // PostgREST renders bytea as a hex string with a leading backslash-x.
    if (value is! String || !value.startsWith(r'\x')) return null;
    final hex = value.substring(2);
    return Uint8List.fromList([
      for (var i = 0; i + 1 < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }

  /// Builds the policy body from the database's independently enforced view.
  ///
  /// These are three fixed, KB-scoped reads rather than one read per member or
  /// document. Only identifiers and roles cross this boundary; no document
  /// content is needed to sign authorization metadata.
  Future<WorkspacePolicy> policySnapshot(String kbId) async {
    final rows = await Future.wait<Object?>([
      client.from('knowledge_bases').select('owner_id').eq('id', kbId).single(),
      client
          .from('kb_members')
          .select('user_id, role, accepted_at')
          .eq('kb_id', kbId),
      client
          .from('documents')
          .select('id, minimum_publish_role')
          .eq('kb_id', kbId),
    ]);

    final kb = Map<String, Object?>.from(rows[0]! as Map);
    final ownerId = kb['owner_id'] as String;
    final members = <String, PolicyRole>{};
    for (final raw in rows[1]! as List) {
      final row = Map<String, Object?>.from(raw as Map);
      if (row['accepted_at'] == null) continue;
      final userId = row['user_id'];
      final role = PolicyRole.fromWire(row['role']);
      if (userId is String && role != null) members[userId] = role;
    }
    // owner_id is the database's canonical ownership fact. A malformed or
    // partially migrated membership row must not produce a policy that omits
    // the owner who is allowed to repair it.
    members[ownerId] = PolicyRole.owner;

    final protected = <String, ProtectedFile>{};
    for (final raw in rows[2]! as List) {
      final row = Map<String, Object?>.from(raw as Map);
      final fileId = row['id'];
      final role = PolicyRole.fromWire(row['minimum_publish_role']);
      if (fileId is String && role != null) {
        protected[fileId] = ProtectedFile(
          fileId: fileId,
          minimumPublishRole: role,
        );
      }
    }

    return WorkspacePolicy(
      kbId: kbId,
      ownerId: ownerId,
      members: members,
      protectedFiles: protected,
      issuedAt: DateTime.now().toUtc(),
    );
  }

  /// PostgREST renders `bytea` as a hex string. Base64 would be smaller, but
  /// Postgres only decodes it through an explicit `decode(...)` call, which a
  /// parameterised RPC cannot express.
  static String _toPostgresBytea(List<int> bytes) {
    final buffer = StringBuffer(r'\x');
    for (final byte in bytes) {
      buffer.write((byte & 0xff).toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }
}

/// Test-only window onto the wire encoding. The encoder is private because
/// nothing outside this file should be building bytea literals; it is verified
/// directly because a padding bug there is invisible until updates corrupt.
@visibleForTesting
abstract final class CrdtSyncRepositoryTestAccess {
  static String bytea(List<int> bytes) =>
      CrdtSyncRepository._toPostgresBytea(bytes);
}
