import 'package:dayseven/shared/backend/retry_budget.dart';
import 'package:dayseven/shared/backend/supabase_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  late DateTime now;
  RetryBudget budget() => RetryBudget(clock: () => now);

  setUp(() => now = DateTime.utc(2026, 8, 26, 12));

  test('a fresh key is always allowed', () {
    expect(budget().allows('doc-1'), isTrue);
  });

  test('one failure imposes a wait before the next attempt', () {
    final b = budget()..recordFailure('doc-1');
    expect(b.allows('doc-1'), isFalse);
    expect(b.remaining('doc-1'), const Duration(milliseconds: 500));

    now = now.add(const Duration(milliseconds: 501));
    expect(b.allows('doc-1'), isTrue);
  });

  test('consecutive failures back off exponentially', () {
    final b = budget();
    final waits = <Duration>[];
    for (var i = 0; i < 4; i++) {
      b.recordFailure('doc-1');
      waits.add(b.remaining('doc-1')!);
      now = now.add(waits.last + const Duration(milliseconds: 1));
    }
    expect(waits, const [
      Duration(milliseconds: 500),
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 4),
    ]);
  });

  test('backoff is capped at the ceiling', () {
    final b = RetryBudget(
      clock: () => now,
      maxConsecutiveFailures: 100,
      firstDelay: const Duration(seconds: 1),
      ceiling: const Duration(seconds: 10),
    );
    for (var i = 0; i < 20; i++) {
      b.recordFailure('doc-1');
      now = now.add(const Duration(minutes: 1));
    }
    b.recordFailure('doc-1');
    expect(b.remaining('doc-1'), const Duration(seconds: 10));
  });

  test('the budget is spent after maxConsecutiveFailures and stays spent', () {
    final b = budget();
    for (var i = 0; i < 5; i++) {
      b.recordFailure('doc-1');
    }
    expect(b.isExhausted('doc-1'), isTrue);
    // This is the property that ends the loop: no amount of waiting revives it.
    now = now.add(const Duration(days: 1));
    expect(b.allows('doc-1'), isFalse);
    expect(b.remaining('doc-1'), Duration.zero);
  });

  test('a landed write clears the streak', () {
    final b = budget();
    for (var i = 0; i < 5; i++) {
      b.recordFailure('doc-1');
    }
    b.recordSuccess('doc-1');
    expect(b.allows('doc-1'), isTrue);
    expect(b.isExhausted('doc-1'), isFalse);
  });

  test('a fresh edit revives an exhausted key', () {
    final b = budget();
    for (var i = 0; i < 5; i++) {
      b.recordFailure('doc-1');
    }
    b.reset('doc-1');
    expect(b.allows('doc-1'), isTrue);
  });

  test('keys do not interfere', () {
    final b = budget();
    for (var i = 0; i < 5; i++) {
      b.recordFailure('doc-1');
    }
    expect(b.isExhausted('doc-1'), isTrue);
    expect(b.allows('doc-2'), isTrue);
  });

  test('a doomed request cannot be resent more than the budget allows', () {
    // The 2026-08-25 outage in miniature: a caller that always fails and always
    // immediately retries. The budget is what makes that terminate.
    final b = budget();
    var attempts = 0;
    while (b.allows('doc-1')) {
      attempts++;
      b.recordFailure('doc-1');
      now = now.add(const Duration(hours: 1)); // never wait-limited
    }
    expect(attempts, 5);
  });

  group('PT429', () {
    test('is recognised as a rate limit, unlike a conflict', () {
      expect(
        isRateLimited(const PostgrestException(message: 'slow down', code: 'PT429')),
        isTrue,
      );
      expect(
        isRateLimited(
          const PostgrestException(message: 'document moved on', code: '40001'),
        ),
        isFalse,
      );
      expect(isRateLimited(const SyncException('nope')), isFalse);
    });

    test('describes itself as a refusal rather than a database fault', () {
      final text = describeError(
        const PostgrestException(
          message: 'too many failed publishes',
          code: 'PT429',
          hint: 'Refresh the Knowledge Base before publishing again.',
        ),
      );
      expect(text, isNot(startsWith('Database:')));
      expect(text, contains('Sync the Knowledge Base'));
      expect(text, contains('Refresh the Knowledge Base before publishing'));
    });
  });
}
