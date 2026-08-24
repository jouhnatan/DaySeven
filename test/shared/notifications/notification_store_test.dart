import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('starts empty', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(notificationStoreProvider), isEmpty);
  });

  test('prepends the newest notification first', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(notificationStoreProvider.notifier);
    store.record(DsNotificationKind.publish, 'first');
    store.record(DsNotificationKind.error, 'second');

    expect(
      container
          .read(notificationStoreProvider)
          .map((notification) => notification.message),
      ['second', 'first'],
    );
  });

  test('keeps only the latest five', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final store = container.read(notificationStoreProvider.notifier);
    for (var i = 0; i < 7; i++) {
      store.record(DsNotificationKind.sync, 'event $i');
    }

    final messages = container
        .read(notificationStoreProvider)
        .map((notification) => notification.message)
        .toList();
    expect(messages.length, kMaxNotifications);
    expect(messages.first, 'event 6');
    expect(messages.last, 'event 2');
    expect(messages.contains('event 1'), isFalse);
  });
}
