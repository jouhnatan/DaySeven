/// Client-side companion to the database's publish circuit breaker.
///
/// A rejected write is not automatically worth repeating. An optimistic-lock
/// conflict in particular means the caller is holding a revision the canonical
/// document has already moved past, so replaying the identical request cannot
/// succeed — it can only be sent again, faster than the person who triggered it
/// could possibly notice.
///
/// On 2026-08-25 that is exactly what happened: a failed submission left its
/// working copy queued, the queue drain re-entered immediately, and the pair
/// issued 5.57M rejected publishes in five hours. `private.publish_gate` now
/// refuses these server-side, but a client that has to be told to stop is still
/// a client sending a thousand doomed requests a second. This is the near half
/// of that guard.
///
/// A budget is keyed by whatever "the same doomed request" means to its owner —
/// usually a document id. Fresh intent (the person edits again, or a write
/// lands) clears the streak; repetition without intent buys an exponentially
/// longer wait.
library;

import 'dart:math' as math;

class RetryBudget {
  RetryBudget({
    this.maxConsecutiveFailures = 5,
    this.firstDelay = const Duration(milliseconds: 500),
    this.ceiling = const Duration(minutes: 2),
    this.jitter = 0.5,
    DateTime Function()? clock,
    math.Random? random,
  }) : _now = clock ?? DateTime.now,
       _random = random ?? math.Random(),
       assert(jitter >= 0 && jitter <= 1);

  /// Failures past this point stop earning a retry at all until something
  /// resets the key. Five is enough to ride out a transient server blip and far
  /// too few to constitute traffic.
  final int maxConsecutiveFailures;

  /// The wait after the first failure. Each subsequent failure doubles it.
  final Duration firstDelay;

  /// The longest a caller is ever asked to wait.
  final Duration ceiling;

  /// How much of each delay is randomised, from 0 (none) to 1 (the whole
  /// delay).
  ///
  /// Backoff alone is not enough when several clients fail at the same instant
  /// for the same reason — they then retry at the same instant too, and the
  /// server sees the same simultaneous burst, just less often. Jitter is what
  /// breaks that lockstep. The default keeps half the delay deterministic so
  /// backoff still grows predictably, and spreads the other half.
  final double jitter;

  final DateTime Function() _now;
  final math.Random _random;
  final Map<String, _Streak> _streaks = <String, _Streak>{};

  /// Whether [key] may be attempted right now.
  ///
  /// False while a backoff is still running, and false permanently once the key
  /// has burned [maxConsecutiveFailures] — until [recordSuccess] or [reset].
  bool allows(String key) => remaining(key) == null;

  /// How long until [key] may be attempted, or null if it may be attempted now.
  ///
  /// Returns [Duration.zero] when the key is exhausted rather than merely
  /// waiting: there is no time at which it becomes attemptable on its own.
  Duration? remaining(String key) {
    final streak = _streaks[key];
    if (streak == null) return null;
    if (streak.failures >= maxConsecutiveFailures) return Duration.zero;
    final wait = streak.retryAt.difference(_now());
    return wait > Duration.zero ? wait : null;
  }

  /// True once [key] has spent its whole budget and will not retry unaided.
  bool isExhausted(String key) =>
      (_streaks[key]?.failures ?? 0) >= maxConsecutiveFailures;

  void recordFailure(String key) {
    final failures = (_streaks[key]?.failures ?? 0) + 1;
    _streaks[key] = _Streak(
      failures: failures,
      retryAt: _now().add(_delayAfter(failures)),
    );
  }

  /// A write landed. Whatever was wrong is no longer wrong.
  void recordSuccess(String key) => _streaks.remove(key);

  /// Fresh intent — the person changed something, so this is a new request
  /// rather than a repeat of the doomed one.
  void reset(String key) => _streaks.remove(key);

  void clear() => _streaks.clear();

  Duration _delayAfter(int failures) {
    final doubled = firstDelay * math.pow(2, failures - 1).toDouble();
    final capped = doubled > ceiling ? ceiling : doubled;
    if (jitter == 0) return capped;
    final micros = capped.inMicroseconds;
    final fixed = (micros * (1 - jitter)).round();
    final spread = micros - fixed;
    return Duration(microseconds: fixed + _random.nextInt(spread + 1));
  }
}

class _Streak {
  const _Streak({required this.failures, required this.retryAt});
  final int failures;
  final DateTime retryAt;
}
