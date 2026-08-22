/// Canonical revision vocabulary shared by local sync and Supabase. Pure Dart.
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
