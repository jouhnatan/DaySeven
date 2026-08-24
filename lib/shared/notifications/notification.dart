/// The in-app notification model: what happened, when, and how it is drawn.
library;

enum DsNotificationKind { publish, sync, share, error }

class DsNotification {
  const DsNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final DsNotificationKind kind;
  final String message;
  final DateTime createdAt;
}
