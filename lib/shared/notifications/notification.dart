/// The in-app notification model: what happened, when, and how it is drawn.
library;

enum DsNotificationKind { publish, sync, share, error }

class DsNotification {
  const DsNotification({
    required this.id,
    required this.kind,
    required this.message,
    required this.createdAt,
    this.heading,
    this.detail,
  });

  final String id;
  final DsNotificationKind kind;
  final String message;
  final DateTime createdAt;

  /// The generic action, shown as the row's header ("Document Published").
  /// When null the UI derives one from [kind].
  final String? heading;

  /// The specifics behind the action, revealed by expanding the row. When
  /// null the flat [message] stands in as the subtext.
  final String? detail;
}
