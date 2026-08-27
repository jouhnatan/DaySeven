import 'package:dayseven/features/notifications/ui/notifications_panel.dart';
import 'package:dayseven/shared/notifications/notification.dart';
import 'package:dayseven/shared/notifications/notification_store.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpPanel(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dsTheme(),
          home: const Scaffold(
            body: SizedBox(
              width: 140,
              height: 400,
              child: NotificationsPanel(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    return container;
  }

  FadeTransition fadeOfRow(WidgetTester tester, String message) =>
      tester.widget<FadeTransition>(
        find
            .ancestor(
              of: find.text(message),
              matching: find.byType(FadeTransition),
            )
            .first,
      );

  testWidgets('shows an empty state before anything is recorded', (
    tester,
  ) async {
    await pumpPanel(tester);

    expect(find.text('Nothing yet.'), findsOneWidget);
    expect(find.byType(AnimatedList), findsNothing);
  });

  testWidgets('fades a new notification in while pushing the rest down', (
    tester,
  ) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);

    store.record(DsNotificationKind.publish, 'first');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    store.record(DsNotificationKind.publish, 'second');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));

    final fade = fadeOfRow(tester, 'second').opacity;
    expect(fade.value, greaterThan(0));
    expect(fade.value, lessThan(1));

    await tester.pump(const Duration(milliseconds: 400));

    expect(fadeOfRow(tester, 'second').opacity.value, 1);
    expect(find.text('second'), findsOneWidget);
    expect(find.text('first'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('second')).dy,
      lessThan(tester.getTopLeft(find.text('first')).dy),
      reason: 'the newest notification sits at the top',
    );
  });

  testWidgets('shows each kind with its own icon', (tester) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);

    store.record(DsNotificationKind.publish, 'a publish');
    store.record(DsNotificationKind.error, 'an error');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byIcon(Icons.cloud_upload_outlined), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });

  testWidgets('labels rows with how long ago they happened', (tester) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);
    final now = DateTime.now();

    store.record(
      DsNotificationKind.publish,
      'just now',
      at: now.subtract(const Duration(minutes: 3)),
    );
    store.record(
      DsNotificationKind.sync,
      'this morning',
      at: now.subtract(const Duration(hours: 5)),
    );
    store.record(
      DsNotificationKind.share,
      'long ago',
      at: now.subtract(const Duration(hours: 30)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('3m'), findsOneWidget);
    expect(find.text('5h'), findsOneWidget);
    expect(find.text('1d+'), findsOneWidget);
  });

  testWidgets('keeps only the latest five', (tester) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);

    for (var i = 0; i < 6; i++) {
      store.record(DsNotificationKind.publish, 'event $i');
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.text('event 0'), findsNothing);
    for (var i = 1; i < 6; i++) {
      expect(find.text('event $i'), findsOneWidget);
    }
  });

  testWidgets('shows a generic heading and the specifics as subtext', (
    tester,
  ) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);

    store.record(
      DsNotificationKind.publish,
      'Published "The Sunken Sea"',
      heading: 'Document Published',
      detail:
          'A document titled "The Sunken Sea" was published by '
          'Johnathan in the "Awayside" folder.',
    );
    store.record(DsNotificationKind.error, 'the file went away');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Document Published'), findsOneWidget);
    expect(
      find.text(
        'A document titled "The Sunken Sea" was published by '
        'Johnathan in the "Awayside" folder.',
      ),
      findsOneWidget,
    );
    expect(find.text('Something Went Wrong'), findsOneWidget);
    expect(find.text('the file went away'), findsOneWidget);
  });

  testWidgets('tapping a row lerps its subtext open and closed', (
    tester,
  ) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);

    const detail =
        'A document titled "The Sunken Sea" was published by Johnathan '
        'in a folder whose name is long enough to wrap onto several '
        'lines inside this narrow island.';
    store.record(
      DsNotificationKind.publish,
      'Published "The Sunken Sea"',
      heading: 'Document Published',
      detail: detail,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final collapsed = tester.getSize(find.text(detail)).height;
    expect(tester.widget<Text>(find.text(detail)).maxLines, 1);

    await tester.tap(find.text('Document Published'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(detail)).maxLines, isNull);
    expect(tester.getSize(find.text(detail)).height, greaterThan(collapsed));

    await tester.tap(find.text('Document Published'));
    await tester.pumpAndSettle();

    expect(tester.widget<Text>(find.text(detail)).maxLines, 1);
    expect(tester.getSize(find.text(detail)).height, collapsed);
  });

  testWidgets('separates rows with lines but leaves the last clean', (
    tester,
  ) async {
    final container = await pumpPanel(tester);
    final store = container.read(notificationStoreProvider.notifier);

    store.record(DsNotificationKind.sync, 'only child');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const Key('notification-divider')), findsNothing);

    store.record(DsNotificationKind.sync, 'second');
    store.record(DsNotificationKind.sync, 'third');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byKey(const Key('notification-divider')), findsNWidgets(2));
  });
}
