/// Revision and change-set types: the shared vocabulary between the local
/// folder and the Supabase mirror. Pure Dart.
library;

import 'package:dayseven/shared/blocks/blocks.dart';

class Revision {
  const Revision({
    required this.id,
    required this.documentId,
    required this.parentRevisionId,
    required this.content,
    required this.contentHash,
    required this.authorId,
    required this.createdAt,
  });

  final String id;
  final String documentId;
  final String? parentRevisionId;
  final BlockDocument content;
  final String contentHash;
  final String authorId;
  final DateTime createdAt;

  static Revision fromRow(Map<String, Object?> row) => Revision(
    id: row['id'] as String,
    documentId: row['document_id'] as String,
    parentRevisionId: row['parent_revision_id'] as String?,
    content: BlockDocument.fromJson(row['content'] as Map<String, Object?>),
    contentHash: row['content_hash'] as String,
    authorId: row['author_id'] as String,
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}

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

  /// The revision the author edited from. The merge base.
  final String? baseRevisionId;

  /// The full proposed block document, as structured JSON — never binary.
  final BlockDocument content;

  final String authorId;

  /// The author's chosen display name, shown to the reviewer.
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

  static ChangeSet fromRow(Map<String, Object?> row) {
    // `profiles` is joined in as a nested object by the select in
    // ChangeSetRepository; fall back to the id when the join is absent.
    final profile = row['profiles'] as Map<String, Object?>?;
    return ChangeSet(
      id: row['id'] as String,
      kbId: row['kb_id'] as String,
      documentId: row['document_id'] as String?,
      targetDocumentId:
          (row['target_document_id'] ?? row['document_id']) as String,
      baseRevisionId: row['base_revision_id'] as String?,
      content: row['content'] == null
          ? BlockDocument(
              id: (row['target_document_id'] ?? row['document_id']) as String,
              title: '',
              blocks: const [],
            )
          : BlockDocument.fromJson(row['content'] as Map<String, Object?>),
      authorId: row['author_id'] as String,
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

/// What Realtime delivers when a proposal is created: identifiers and a name,
/// never document content.
class ProposalNotification {
  const ProposalNotification({
    required this.changeSetId,
    required this.documentId,
    required this.authorDisplayName,
  });

  final String changeSetId;
  final String documentId;
  final String authorDisplayName;

  static ProposalNotification fromPayload(Map<String, Object?> payload) {
    // realtime.send wraps the JSON built in the trigger under `payload`.
    final body = (payload['payload'] as Map<String, Object?>?) ?? payload;
    return ProposalNotification(
      changeSetId: body['change_set_id'] as String,
      documentId: body['document_id'] as String,
      authorDisplayName:
          body['author_display_name'] as String? ?? 'Unknown author',
    );
  }
}
