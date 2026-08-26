/// Who owns this Knowledge Base, and which files are protected.
///
/// Lives at `metadata/yjs/policy.json`, signed by the owner. It travels with
/// the workspace — through the CRDT, a backup, a copied folder — so by the
/// time a client reads it, it has been somewhere untrusted. Believing it
/// unverified would mean taking instructions about who may write from a file
/// anybody could have edited.
///
/// **Nothing here is a permission check on its own.** A client verifying its
/// own policy is advisory: it stops an honest client from broadcasting an edit
/// that would be refused, and stops a tampered file from quietly widening
/// somebody's rights. The enforcement that matters is in Postgres, which
/// checks the same rules against `kb_members` and `documents` on every write
/// and does not consult this file at all.
///
/// The signed bytes are the canonical JSON of everything except the signature,
/// with keys sorted and no insignificant whitespace. Two clients must agree
/// byte-for-byte on what was signed, so the encoding is pinned here rather
/// than left to whatever `jsonEncode` happens to do with map ordering.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/generated/api/policy.dart' as crypto;

/// How much authority a member has, lowest first. Mirrors the database's
/// `kb_members.role` and the ranking in `private.publish_role_rank`.
enum PolicyRole {
  reviewer('reviewer', 1),
  editor('editor', 2),
  coOwner('co_owner', 3),
  owner('owner', 4);

  const PolicyRole(this.wire, this.rank);
  final String wire;
  final int rank;

  bool meets(PolicyRole required) => rank >= required.rank;

  static PolicyRole? fromWire(Object? value) {
    if (value is! String) return null;
    for (final role in PolicyRole.values) {
      if (role.wire == value) return role;
    }
    return null;
  }
}

/// A file that cannot be changed directly by everybody who can edit.
class ProtectedFile {
  const ProtectedFile({required this.fileId, required this.minimumPublishRole});

  /// The workspace file id. Never a path — a path can be renamed out from
  /// under a policy, and a policy that names paths protects the wrong file the
  /// moment somebody moves one.
  final String fileId;

  /// The lowest role permitted to write it directly. Anyone below proposes.
  final PolicyRole minimumPublishRole;

  Map<String, Object?> toJson() => {
    'file_id': fileId,
    'minimum_publish_role': minimumPublishRole.wire,
  };

  static ProtectedFile? fromJson(Object? value) {
    if (value is! Map) return null;
    final fileId = value['file_id'];
    final role = PolicyRole.fromWire(value['minimum_publish_role']);
    if (fileId is! String || fileId.isEmpty || role == null) return null;
    return ProtectedFile(fileId: fileId, minimumPublishRole: role);
  }
}

class WorkspacePolicyException implements Exception {
  const WorkspacePolicyException(this.message);
  final String message;
  @override
  String toString() => message;
}

class WorkspacePolicy {
  const WorkspacePolicy({
    required this.kbId,
    required this.ownerId,
    required this.members,
    required this.protectedFiles,
    required this.issuedAt,
    this.version = 1,
  });

  /// Bumped when the meaning of a field changes. A policy from a version this
  /// build does not understand is refused rather than partially believed.
  static const int currentVersion = 1;

  final int version;
  final String kbId;
  final String ownerId;

  /// user id -> role.
  final Map<String, PolicyRole> members;

  /// file id -> protection.
  final Map<String, ProtectedFile> protectedFiles;

  final DateTime issuedAt;

  PolicyRole? roleOf(String userId) => members[userId];

  /// Whether [userId] may write [fileId] directly, as this policy sees it.
  ///
  /// An unprotected file is writable by any member with an editing role. A
  /// protected one needs the stated rank. A user this policy has never heard
  /// of may write nothing.
  bool canWriteDirectly({required String userId, required String fileId}) {
    final role = members[userId];
    if (role == null) return false;
    if (!role.meets(PolicyRole.editor)) return false;
    final protection = protectedFiles[fileId];
    return protection == null || role.meets(protection.minimumPublishRole);
  }

  bool isProtected(String fileId) => protectedFiles.containsKey(fileId);

  /// Whether two snapshots describe the same authorization rules.
  ///
  /// [issuedAt] is intentionally ignored. Re-signing solely because the app
  /// reopened would create a CRDT update with no policy change.
  bool hasSameRulesAs(WorkspacePolicy other) {
    if (version != other.version ||
        kbId != other.kbId ||
        ownerId != other.ownerId ||
        members.length != other.members.length ||
        protectedFiles.length != other.protectedFiles.length) {
      return false;
    }
    for (final entry in members.entries) {
      if (other.members[entry.key] != entry.value) return false;
    }
    for (final entry in protectedFiles.entries) {
      final otherFile = other.protectedFiles[entry.key];
      if (otherFile == null ||
          otherFile.minimumPublishRole != entry.value.minimumPublishRole) {
        return false;
      }
    }
    return true;
  }

  /// The exact bytes that get signed.
  ///
  /// Keys are emitted in a fixed order and collections are sorted, so the same
  /// policy produces the same bytes on every machine and in every Dart
  /// version. A signature over "whatever jsonEncode did today" is a signature
  /// that stops verifying when something unrelated changes.
  Uint8List canonicalBytes() => Uint8List.fromList(
    utf8.encode(
      jsonEncode({
        'version': version,
        'kb_id': kbId,
        'owner_id': ownerId,
        'issued_at': issuedAt.toUtc().toIso8601String(),
        'members': [
          for (final id in members.keys.toList()..sort())
            {'user_id': id, 'role': members[id]!.wire},
        ],
        'protected_files': [
          for (final id in protectedFiles.keys.toList()..sort())
            protectedFiles[id]!.toJson(),
        ],
      }),
    ),
  );

  /// Signs this policy and renders the file that goes on disk.
  Future<String> signedJson(List<int> ownerSecretKey) async {
    final body = canonicalBytes();
    final signature = await crypto.policySign(
      secretKey: ownerSecretKey,
      message: body,
    );
    return jsonEncode({
      'policy': jsonDecode(utf8.decode(body)),
      'signature': base64Encode(signature),
    });
  }

  static WorkspacePolicy _fromBody(Map<String, Object?> body) {
    final version = body['version'];
    if (version is! int) {
      throw const WorkspacePolicyException('policy.json has no version');
    }
    if (version > currentVersion) {
      throw WorkspacePolicyException(
        'policy.json is version $version; this build understands '
        '$currentVersion. Update DaySeven before opening this Knowledge Base.',
      );
    }
    final kbId = body['kb_id'];
    final ownerId = body['owner_id'];
    if (kbId is! String ||
        kbId.isEmpty ||
        ownerId is! String ||
        ownerId.isEmpty) {
      throw const WorkspacePolicyException(
        'policy.json is missing its Knowledge Base or owner',
      );
    }

    final members = <String, PolicyRole>{};
    for (final entry in (body['members'] as List? ?? const [])) {
      if (entry is! Map) continue;
      final id = entry['user_id'];
      final role = PolicyRole.fromWire(entry['role']);
      if (id is String && id.isNotEmpty && role != null) members[id] = role;
    }

    final protectedFiles = <String, ProtectedFile>{};
    for (final entry in (body['protected_files'] as List? ?? const [])) {
      final file = ProtectedFile.fromJson(entry);
      if (file != null) protectedFiles[file.fileId] = file;
    }

    return WorkspacePolicy(
      version: version,
      kbId: kbId,
      ownerId: ownerId,
      members: members,
      protectedFiles: protectedFiles,
      issuedAt:
          DateTime.tryParse(body['issued_at'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  /// Parses and verifies. Returns a policy only when the signature is this
  /// exact document signed by [ownerPublicKey].
  ///
  /// Throws rather than returning null: an unverifiable policy is not an
  /// absent one, and the two must never be handled by the same branch. A
  /// missing file means a Knowledge Base with no protected content; a file
  /// that fails to verify means somebody changed it.
  static Future<WorkspacePolicy> verified(
    String json, {
    required List<int> ownerPublicKey,
    required String expectedKbId,
  }) async {
    final Object? parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      throw const WorkspacePolicyException('policy.json is not valid JSON');
    }
    if (parsed is! Map) {
      throw const WorkspacePolicyException('policy.json is not an object');
    }
    final body = parsed['policy'];
    final signature = parsed['signature'];
    if (body is! Map || signature is! String) {
      throw const WorkspacePolicyException(
        'policy.json is missing its body or signature',
      );
    }

    final policy = _fromBody(Map<String, Object?>.from(body));

    // Verify before believing anything, including which KB this is for.
    final Uint8List signatureBytes;
    try {
      signatureBytes = base64Decode(signature);
    } on FormatException {
      throw const WorkspacePolicyException(
        'policy.json signature is malformed',
      );
    }

    final bool ok;
    try {
      ok = await crypto.policyVerify(
        publicKey: ownerPublicKey,
        message: policy.canonicalBytes(),
        signature: signatureBytes,
      );
    } on Object catch (error) {
      // A signature that *could not be checked* is not a signature that
      // failed. Both refuse the policy, but they are different sentences.
      throw WorkspacePolicyException(
        'policy.json signature could not be checked: $error',
      );
    }
    if (!ok) {
      throw const WorkspacePolicyException(
        'policy.json does not match its signature. It has been modified since '
        'the owner signed it, and none of its permissions can be trusted.',
      );
    }

    // A validly signed policy for a *different* Knowledge Base is a real
    // attack: copy a folder's policy into another workspace and inherit its
    // ownership. The signature proves who wrote it, not what it is for.
    if (policy.kbId != expectedKbId) {
      throw WorkspacePolicyException(
        'policy.json is signed for Knowledge Base ${policy.kbId}, not '
        '$expectedKbId.',
      );
    }
    return policy;
  }
}
