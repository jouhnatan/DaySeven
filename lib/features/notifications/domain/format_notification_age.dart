/// Relative age labels for notifications: 0-60m for minutes, 1-24h for
/// hours, and the constant `1d+` for anything longer than a day.
library;

String formatNotificationAge(DateTime createdAt, {DateTime? now}) {
  final elapsed = (now ?? DateTime.now()).difference(createdAt);
  final minutes = elapsed.isNegative ? 0 : elapsed.inMinutes;
  if (minutes > Duration.minutesPerDay) return '1d+';
  if (minutes >= 60) return '${minutes ~/ 60}h';
  return '${minutes}m';
}
