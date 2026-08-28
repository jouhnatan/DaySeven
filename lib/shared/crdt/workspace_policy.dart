/// Who owns this Knowledge Base, and which files are protected.
///
/// Postgres is the authority. `kb_members.role` and the `documents`
/// `protection_class` / `minimum_publish_role` columns are the facts, and row
/// level security already restricts every one of them to members of the
/// Knowledge Base. A client reads those rows with its own credentials and
/// builds the policy from them, so what it holds came from the authority over
/// an authenticated channel rather than from a file that travelled with the
/// workspace.
///
/// A copy is cached at `metadata/yjs/policy.json` purely so a member who
/// cannot reach the network can keep working with the protection rules they
/// last saw. It carries no signature because nothing trusts it on its own: a
/// client that has never reached the authority has no policy at all, and
/// refuses to start collaborating rather than assuming nothing is protected.
///
/// **Nothing here is a permission check on its own.** The relay decides who
/// may write by verifying membership against Postgres on every connection,
/// and re-checking it while the socket is open. What this file adds is which
/// *files* are protected, which the relay cannot know because it never decodes
/// a CRDT payload. That is what routes an edit to a protected file into a
/// proposal instead of a direct broadcast.
///
/// Keys are emitted in a fixed order and collections sorted, so the same
/// policy produces the same bytes on every machine and in every Dart version.
library;

import 'dart:convert';
import 'dart:typed_data';

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

  /// The canonical encoding, used for the offline cache and for comparing two
  /// policies byte for byte.
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

  /// Renders the offline cache file.
  String cacheJson() => utf8.decode(canonicalBytes());

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

  /// Reads a cached policy written by [cacheJson].
  ///
  /// Throws rather than returning null: a damaged cache is not an absent one,
  /// and the two must never take the same branch. No cache at all means this
  /// device has never reached the authority, which stops collaboration; a
  /// cache that will not parse means something rewrote it, and believing it
  /// would mean taking protection rules from a file anybody could have edited.
  static WorkspacePolicy fromCache(
    String json, {
    required String expectedKbId,
  }) {
    final Object? parsed;
    try {
      parsed = jsonDecode(json);
    } on FormatException {
      throw const WorkspacePolicyException('policy.json is not valid JSON');
    }
    if (parsed is! Map) {
      throw const WorkspacePolicyException('policy.json is not an object');
    }

    final policy = _fromBody(Map<String, Object?>.from(parsed));

    // A cached policy for a *different* Knowledge Base is a real mix-up: copy
    // a folder's cache into another workspace and it would carry that
    // workspace's ownership and protection across with it.
    if (policy.kbId != expectedKbId) {
      throw WorkspacePolicyException(
        'policy.json is cached for Knowledge Base ${policy.kbId}, not '
        '$expectedKbId.',
      );
    }
    return policy;
  }
}
