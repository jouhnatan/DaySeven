/// The security event log.
///
/// Records the things you need to answer "what happened" after the fact:
/// who joined which channel, whose message was refused and why, and which
/// limits somebody hit. It exists because collaboration now accepts input from
/// another machine, and a refusal that leaves no trace is indistinguishable
/// from an attack that worked.
///
/// **The vocabulary is closed on purpose.** An event is a
/// [SecurityEventKind] plus a small map of identifiers, and the writer
/// strips anything that is not a scalar. There is no free-text field a caller
/// can accidentally fill with a paragraph of somebody's private document. The
/// rule from the plan is absolute: never log document contents, private keys,
/// invite codes, or reusable credentials — so the shape here makes doing that
/// awkward rather than merely forbidden.
///
/// Volume is bounded twice. Identical events collapse into a count rather than
/// repeating, because the failure mode this log is most likely to witness is
/// something happening a thousand times a second; and the file is rotated at a
/// fixed size, so a hostile peer cannot fill the disk by being refused.
library;

import 'dart:convert';
import 'dart:io';

/// Everything the log is allowed to say happened.
enum SecurityEventKind {
  /// Joined or left a Realtime topic.
  channelJoined('channel.joined'),
  channelLeft('channel.left'),
  channelError('channel.error'),

  /// Membership or role changed. Replaces the device pairing/revocation events
  /// from the peer-to-peer design, which no longer exist.
  membershipChanged('membership.changed'),

  /// The server refused to authenticate the caller.
  authenticationFailed('auth.failed'),

  /// The caller was authenticated but not permitted — a role too low, or an
  /// edit to a protected file that requires review.
  authorizationFailed('authz.failed'),

  /// A message was over a size limit, or a caller was over a rate limit.
  limitExceeded('limit.exceeded'),

  /// A message did not conform to the protocol: unknown type, malformed
  /// envelope, incoherent chunking, or a replay.
  protocolError('protocol.error'),

  /// An update was applied to a staging document, inspected, and refused
  /// before it could reach canonical state.
  updateRejected('update.rejected');

  const SecurityEventKind(this.wire);
  final String wire;
}

/// One event. [facts] carries identifiers only.
class SecurityEvent {
  SecurityEvent(this.kind, {Map<String, Object?> facts = const {}})
    : facts = sanitizeFacts(facts);

  final SecurityEventKind kind;
  final Map<String, Object?> facts;

  /// Keys whose values are dropped outright, whatever they contain. A belt to
  /// the braces of "callers should not pass these".
  static const Set<String> forbiddenKeys = {
    'content',
    'text',
    'body',
    'payload',
    'bytes',
    'token',
    'key',
    'secret',
    'password',
    'invite',
    'invite_code',
    'jwt',
    'authorization',
  };

  /// Reduces arbitrary input to loggable identifiers.
  ///
  /// Scalars survive; anything structured is replaced by its type name,
  /// because a nested object is exactly how a document ends up in a log. Long
  /// strings are truncated — an id is short, and something long is not an id.
  static Map<String, Object?> sanitizeFacts(Map<String, Object?> facts) {
    final clean = <String, Object?>{};
    for (final entry in facts.entries) {
      final key = entry.key.toLowerCase();
      if (forbiddenKeys.contains(key)) continue;
      final value = entry.value;
      clean[entry.key] = switch (value) {
        null => null,
        bool() || int() || double() => value,
        String() => value.length <= 128 ? value : '<${value.length} chars>',
        _ => '<${value.runtimeType}>',
      };
    }
    return clean;
  }

  Map<String, Object?> toJson(DateTime at, int count) => {
    'at': at.toUtc().toIso8601String(),
    'kind': kind.wire,
    if (count > 1) 'count': count,
    ...facts,
  };
}

/// Where events go. Separated so the log can be tested without a filesystem
/// and so App settings can show recent events without reading the file.
abstract class SecuritySink {
  void write(String line);
}

class SecurityLog {
  SecurityLog({
    required this.sink,
    this.collapseWindow = const Duration(seconds: 5),
    this.recentLimit = 100,
    DateTime Function()? clock,
  }) : _now = clock ?? DateTime.now;

  final SecuritySink sink;

  /// Identical events inside this window are counted rather than repeated.
  /// A refusal loop is one line saying it happened 4,000 times, not 4,000
  /// lines — the log has to survive the incident it is recording.
  final Duration collapseWindow;

  /// How many events to keep in memory for App settings to display.
  final int recentLimit;

  final DateTime Function() _now;
  final List<String> _recent = <String>[];

  String? _lastSignature;
  DateTime? _lastAt;
  int _lastCount = 0;
  Map<String, Object?>? _lastJson;

  /// Recent events, newest last, for display. Never the whole file.
  List<String> get recent => List.unmodifiable(_recent);

  void record(SecurityEventKind kind, {Map<String, Object?> facts = const {}}) {
    final event = SecurityEvent(kind, facts: facts);
    final at = _now();
    final signature = '${kind.wire}|${jsonEncode(event.facts)}';

    if (signature == _lastSignature &&
        _lastAt != null &&
        at.difference(_lastAt!) <= collapseWindow) {
      _lastCount++;
      return;
    }

    _flushCollapsed();
    _lastSignature = signature;
    _lastAt = at;
    _lastCount = 1;
    _lastJson = event.toJson(at, 1);
  }

  /// Writes out whatever is being collapsed. Call before reading the file or
  /// shutting down, or the last run of repeats is never written.
  void flush() {
    _flushCollapsed();
    _lastSignature = null;
    _lastAt = null;
    _lastCount = 0;
    _lastJson = null;
  }

  void _flushCollapsed() {
    final json = _lastJson;
    if (json == null || _lastCount == 0) return;
    final line = jsonEncode({
      ...json,
      if (_lastCount > 1) 'count': _lastCount,
    });
    sink.write(line);
    _recent.add(line);
    while (_recent.length > recentLimit) {
      _recent.removeAt(0);
    }
    _lastJson = null;
    _lastCount = 0;
  }
}

/// Appends JSON lines to a file, rotating at [maxBytes].
///
/// One generation of history is kept. Two files of a bounded size is the whole
/// disk cost, which is the property that matters: being refused repeatedly
/// must not be a way to fill somebody's disk.
class SecurityLogFileSink implements SecuritySink {
  SecurityLogFileSink(this.file, {this.maxBytes = 512 * 1024});

  final File file;
  final int maxBytes;

  @override
  void write(String line) {
    try {
      if (file.existsSync() && file.lengthSync() + line.length > maxBytes) {
        final previous = File('${file.path}.1');
        if (previous.existsSync()) previous.deleteSync();
        file.renameSync(previous.path);
      }
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('$line\n', mode: FileMode.append, flush: false);
    } on FileSystemException {
      // A log that cannot be written must not take the app down with it.
    }
  }
}

/// Discards everything. The default when there is nowhere sensible to write.
class NullSecuritySink implements SecuritySink {
  const NullSecuritySink();
  @override
  void write(String line) {}
}
