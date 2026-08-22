/// Protection metadata that controls whether publishing is immediate or
/// reviewed for a particular document.
library;

enum DocumentProtectionClass {
  protected('protected');

  const DocumentProtectionClass(this.databaseValue);
  final String databaseValue;

  static DocumentProtectionClass? fromDatabase(Object? value) =>
      switch (value) {
        'protected' => DocumentProtectionClass.protected,
        _ => null,
      };
}

enum MinimumPublishRole {
  editor('editor', 1, 'Editor'),
  coOwner('co_owner', 2, 'Co-Owner'),
  owner('owner', 3, 'Owner');

  const MinimumPublishRole(this.databaseValue, this.rank, this.label);
  final String databaseValue;
  final int rank;
  final String label;

  static MinimumPublishRole? fromDatabase(Object? value) => switch (value) {
    'editor' => MinimumPublishRole.editor,
    'co_owner' => MinimumPublishRole.coOwner,
    'owner' => MinimumPublishRole.owner,
    _ => null,
  };
}

class DocumentProtection {
  const DocumentProtection({
    required this.protectionClass,
    required this.minimumPublishRole,
  });

  final DocumentProtectionClass protectionClass;
  final MinimumPublishRole minimumPublishRole;

  @override
  bool operator ==(Object other) =>
      other is DocumentProtection &&
      other.protectionClass == protectionClass &&
      other.minimumPublishRole == minimumPublishRole;

  @override
  int get hashCode => Object.hash(protectionClass, minimumPublishRole);

  static DocumentProtection? fromRow(Map<String, Object?> row) {
    final protectionClass = DocumentProtectionClass.fromDatabase(
      row['protection_class'],
    );
    final minimumRole = MinimumPublishRole.fromDatabase(
      row['minimum_publish_role'],
    );
    if (protectionClass == null || minimumRole == null) return null;
    return DocumentProtection(
      protectionClass: protectionClass,
      minimumPublishRole: minimumRole,
    );
  }
}

enum DocumentPublishDisposition { published, proposed }

class DocumentPublishReceipt {
  const DocumentPublishReceipt.published(this.id)
    : disposition = DocumentPublishDisposition.published;

  const DocumentPublishReceipt.proposed(this.id)
    : disposition = DocumentPublishDisposition.proposed;

  final DocumentPublishDisposition disposition;
  final String id;

  bool get wasPublished => disposition == DocumentPublishDisposition.published;

  factory DocumentPublishReceipt.fromRpc(Object? value) {
    final raw = value is List ? value.single : value;
    final row = Map<String, Object?>.from(raw! as Map);
    final id = row['id'] as String;
    return switch (row['outcome']) {
      'published' => DocumentPublishReceipt.published(id),
      'proposed' => DocumentPublishReceipt.proposed(id),
      final outcome => throw StateError('Unknown publish outcome: $outcome'),
    };
  }
}
