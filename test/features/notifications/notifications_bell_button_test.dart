import 'package:dayseven/features/notifications/ui/notifications_bell_button.dart';
import 'package:dayseven/features/notifications/ui/notifications_panel.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpBell(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: NotificationsBellButton(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return container;
  }

  /// While the panel is open the dismiss barrier covers the bell, so a click
  /// aimed at it lands there instead — which closes the panel just the same.
  Future<void> tapBell(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const Key('notifications-bell-button')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('the bell is unmarked until something is recorded', (
    tester,
  ) async {
    final container = await pumpBell(tester);

    expect(find.byKey(const Key('notifications-bell-dot')), findsNothing);

    container
        .read(notificationStoreProvider.notifier)
        .record(DsNotificationKind.publish, 'Saved Timeline.md');
    await tester.pump();

    expect(find.byKey(const Key('notifications-bell-dot')), findsOneWidget);
  });

  testWidgets('the panel opens on the bell and closes on a second click', (
    tester,
  ) async {
    await pumpBell(tester);

    expect(find.byType(NotificationsPanel), findsNothing);

    await tapBell(tester);
    expect(find.byKey(const Key('notifications-popover')), findsOneWidget);
    expect(find.byType(NotificationsPanel), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);

    await tapBell(tester);
    expect(find.byType(NotificationsPanel), findsNothing);
  });

  testWidgets('a click anywhere outside dismisses the panel', (tester) async {
    await pumpBell(tester);
    await tapBell(tester);

    expect(find.byType(NotificationsPanel), findsOneWidget);

    await tester.tapAt(const Offset(600, 500));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPanel), findsNothing);
  });

  testWidgets('a row still expands its detail inside the panel', (
    tester,
  ) async {
    final container = await pumpBell(tester);
    container
        .read(notificationStoreProvider.notifier)
        .record(
          DsNotificationKind.publish,
          'Saved',
          heading: 'Document Published',
          detail: 'Timeline.md was published to the Knowledge Base.',
        );
    await tester.pump();
    await tapBell(tester);

    Text detailText() => tester.widget<Text>(
      find.text('Timeline.md was published to the Knowledge Base.'),
    );

    expect(detailText().maxLines, 1);

    // A popup menu would have swallowed this tap and closed itself, which is
    // why the panel is an anchored overlay instead.
    await tester.tap(find.text('Document Published'));
    await tester.pumpAndSettle();

    expect(find.byType(NotificationsPanel), findsOneWidget);
    expect(detailText().maxLines, isNull);
  });
}
