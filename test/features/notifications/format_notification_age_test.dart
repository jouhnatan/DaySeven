import 'package:dayseven/features/notifications/domain/format_notification_age.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime(2026, 8, 24, 12);

  DateTime minutesAgo(int minutes) => now.subtract(Duration(minutes: minutes));

  test('0-60m covers the first hour', () {
    expect(formatNotificationAge(minutesAgo(0), now: now), '0m');
    expect(formatNotificationAge(minutesAgo(1), now: now), '1m');
    expect(formatNotificationAge(minutesAgo(45), now: now), '45m');
    expect(formatNotificationAge(minutesAgo(59), now: now), '59m');
  });

  test('1-24h covers the first day', () {
    expect(formatNotificationAge(minutesAgo(60), now: now), '1h');
    expect(formatNotificationAge(minutesAgo(90), now: now), '1h');
    expect(formatNotificationAge(minutesAgo(23 * 60 + 59), now: now), '23h');
    expect(formatNotificationAge(minutesAgo(24 * 60), now: now), '24h');
  });

  test('anything longer than a day is 1d+', () {
    expect(formatNotificationAge(minutesAgo(24 * 60 + 1), now: now), '1d+');
    expect(formatNotificationAge(minutesAgo(48 * 60), now: now), '1d+');
  });

  test('clock skew reads as just now', () {
    expect(formatNotificationAge(now.add(const Duration(minutes: 5)), now: now), '0m');
  });
}
