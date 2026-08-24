/// The session's notifications: the latest events, newest first, capped at
/// five. Nothing here is persisted; the list starts empty every launch.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:dayseven/shared/notifications/notification.dart';

const int kMaxNotifications = 5;

class NotificationStore extends Notifier<List<DsNotification>> {
  final Uuid _uuid = const Uuid();

  @override
  List<DsNotification> build() => const [];

  void record(
    DsNotificationKind kind,
    String message, {
    DateTime? at,
  }) {
    final notification = DsNotification(
      id: _uuid.v7(),
      kind: kind,
      message: message,
      createdAt: at ?? DateTime.now(),
    );
    state = [
      notification,
      ...state,
    ].take(kMaxNotifications).toList(growable: false);
  }
}

final notificationStoreProvider =
    NotifierProvider<NotificationStore, List<DsNotification>>(
      NotificationStore.new,
    );
