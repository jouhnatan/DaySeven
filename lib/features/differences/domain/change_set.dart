/// Reviewed-edit domain types. Pure Dart: UI and Supabase stay outside.
library;

import 'package:dayseven/shared/blocks/blocks.dart';

enum ChangeSetStatus { pending, approved, rejected, withdrawn, superseded }

enum ChangeSetOperation { create, update, delete }

class ChangeSet {
  const ChangeSet({
    required this.id,
    required this.kbId,
    required this.documentId,
    required this.targetDocumentId,
    required this.baseRevisionId,
    required this.content,
    required this.authorId,
    required this.authorUsername,
    required this.authorDisplayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.operation = ChangeSetOperation.update,
    this.proposedPath,
    this.reviewNote,
    this.resultingRevisionId,
    this.resolvedAt,
    this.resolvedBy,
  });

  final String id;
  final String kbId;
  final String? documentId;
  final String targetDocumentId;
  final String? baseRevisionId;
  final BlockDocument content;
  final String authorId;
  final String authorUsername;
  final String authorDisplayName;
  final ChangeSetStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final ChangeSetOperation operation;
  final String? proposedPath;
  final String? reviewNote;
  final String? resultingRevisionId;
  final DateTime? resolvedAt;
  final String? resolvedBy;

  String get usernameLabel {
    final normalized = authorUsername.trim().replaceFirst(RegExp(r'^@+'), '');
    return '@${normalized.isEmpty ? 'unknown' : normalized}';
  }

  static ChangeSet fromRow(Map<String, Object?> row) {
    final profile = row['profiles'] as Map<String, Object?>?;
    final targetId =
        (row['target_document_id'] ?? row['document_id']) as String;
    return ChangeSet(
      id: row['id'] as String,
      kbId: row['kb_id'] as String,
      documentId: row['document_id'] as String?,
      targetDocumentId: targetId,
      baseRevisionId: row['base_revision_id'] as String?,
      content: row['content'] == null
          ? BlockDocument(id: targetId, title: '', blocks: const [])
          : BlockDocument.fromJson(row['content'] as Map<String, Object?>),
      authorId: row['author_id'] as String,
      authorUsername: profile?['username'] as String? ?? 'unknown',
      authorDisplayName:
          profile?['display_name'] as String? ?? 'Unknown author',
      status: ChangeSetStatus.values.byName(row['status'] as String),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(
        (row['updated_at'] ?? row['created_at']) as String,
      ),
      operation: ChangeSetOperation.values.byName(
        (row['operation'] as String?) ?? 'update',
      ),
      proposedPath: row['proposed_path'] as String?,
      reviewNote: row['review_note'] as String?,
      resultingRevisionId: row['resulting_revision_id'] as String?,
      resolvedAt: row['resolved_at'] == null
          ? null
          : DateTime.parse(row['resolved_at'] as String),
      resolvedBy: row['resolved_by'] as String?,
    );
  }
}

/// A Realtime wake-up contains identifiers only, never proposal content.
class ProposalNotification {
  const ProposalNotification({
    required this.changeSetId,
    required this.documentId,
  });

  final String changeSetId;
  final String documentId;

  static ProposalNotification fromPayload(Map<String, Object?> payload) {
    final body = (payload['payload'] as Map<String, Object?>?) ?? payload;
    return ProposalNotification(
      changeSetId: body['change_set_id'] as String,
      documentId: body['document_id'] as String,
    );
  }
}
