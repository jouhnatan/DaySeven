/// What the security log will and will not write down.
///
/// The refusals matter more than the records here: a log that can be made to
/// contain document text, or to grow without bound, is worse than no log.
library;

import 'dart:convert';
import 'dart:io';

import 'package:dayseven/shared/security/security_log.dart';
import 'package:flutter_test/flutter_test.dart';

class MemorySink implements SecuritySink {
  final List<String> lines = [];
  @override
  void write(String line) => lines.add(line);
}

void main() {
  late MemorySink sink;
  late DateTime now;
  SecurityLog log() => SecurityLog(sink: sink, clock: () => now);

  setUp(() {
    sink = MemorySink();
    now = DateTime.utc(2026, 8, 26, 12);
  });

  Map<String, Object?> decoded(int index) =>
      jsonDecode(sink.lines[index]) as Map<String, Object?>;

  group('what it records', () {
    test('writes the kind, the time, and the identifiers', () {
      log()
        ..record(
          SecurityEventKind.channelJoined,
          facts: {'topic': 'crdt:kb-1', 'user_id': 'u-1'},
        )
        ..flush();
      expect(sink.lines, hasLength(1));
      final event = decoded(0);
      expect(event['kind'], 'channel.joined');
      expect(event['topic'], 'crdt:kb-1');
      expect(event['user_id'], 'u-1');
      expect(event['at'], '2026-08-26T12:00:00.000Z');
    });

    test('every event kind has a stable wire name', () {
      expect(
        SecurityEventKind.values.map((k) => k.wire).toSet(),
        hasLength(SecurityEventKind.values.length),
      );
      expect(SecurityEventKind.authorizationFailed.wire, 'authz.failed');
    });
  });

  group('what it refuses to record', () {
    test('drops forbidden keys outright', () {
      final facts = {
        for (final key in SecurityEvent.forbiddenKeys) key: 'sensitive',
        'user_id': 'u-1',
      };
      log()
        ..record(SecurityEventKind.updateRejected, facts: facts)
        ..flush();
      final event = decoded(0);
      expect(event['user_id'], 'u-1');
      for (final key in SecurityEvent.forbiddenKeys) {
        expect(event.containsKey(key), isFalse, reason: key);
      }
      expect(sink.lines.single, isNot(contains('sensitive')));
    });

    test('forbidden keys are matched case-insensitively', () {
      log()
        ..record(SecurityEventKind.updateRejected, facts: {'Token': 'abc123'})
        ..flush();
      expect(sink.lines.single, isNot(contains('abc123')));
    });

    test('replaces structured values with their type, never their content', () {
      log()
        ..record(
          SecurityEventKind.updateRejected,
          facts: {
            'doc': {'title': 'Aldric', 'blocks': ['secret prose']},
            'ids': ['a', 'b'],
          },
        )
        ..flush();
      final line = sink.lines.single;
      expect(line, isNot(contains('secret prose')));
      expect(line, isNot(contains('Aldric')));
      expect(decoded(0)['doc'], startsWith('<'));
    });

    test('truncates a long string rather than writing it', () {
      // A document pasted into a fact is the realistic accident. An id is
      // short; anything long is not an id.
      final prose = 'The moor is wide. ' * 100;
      log()
        ..record(SecurityEventKind.protocolError, facts: {'note': prose})
        ..flush();
      expect(sink.lines.single, isNot(contains('The moor is wide')));
      expect(decoded(0)['note'], '<1800 chars>');
    });
  });

  group('bounded volume', () {
    test('collapses a burst of identical events into one counted line', () {
      // The incident this log is most likely to witness is something happening
      // a thousand times a second. It has to survive recording that.
      final l = log();
      for (var i = 0; i < 5000; i++) {
        l.record(
          SecurityEventKind.limitExceeded,
          facts: {'user_id': 'u-1', 'limit': 'rate'},
        );
      }
      l.flush();
      expect(sink.lines, hasLength(1));
      expect(decoded(0)['count'], 5000);
    });

    test('a different event ends the collapse', () {
      log()
        ..record(SecurityEventKind.limitExceeded, facts: {'user_id': 'u-1'})
        ..record(SecurityEventKind.limitExceeded, facts: {'user_id': 'u-1'})
        ..record(SecurityEventKind.limitExceeded, facts: {'user_id': 'u-2'})
        ..flush();
      expect(sink.lines, hasLength(2));
      expect(decoded(0)['count'], 2);
      expect(decoded(1)['user_id'], 'u-2');
    });

    test('collapsing stops after the window, so time still advances', () {
      final l = log()
        ..record(SecurityEventKind.limitExceeded, facts: {'user_id': 'u-1'});
      now = now.add(const Duration(seconds: 30));
      l
        ..record(SecurityEventKind.limitExceeded, facts: {'user_id': 'u-1'})
        ..flush();
      expect(sink.lines, hasLength(2));
    });

    test('the in-memory recent buffer does not grow without bound', () {
      final l = SecurityLog(sink: sink, clock: () => now, recentLimit: 10);
      for (var i = 0; i < 100; i++) {
        l.record(SecurityEventKind.protocolError, facts: {'seq': i});
      }
      l.flush();
      expect(l.recent, hasLength(10));
    });
  });

  group('the audit surface', () {
    test('covers every event the plan asks to be recorded', () {
      // Connection, session identity, authentication and authorization
      // failures, limit violations, protocol errors, membership changes.
      final kinds = SecurityEventKind.values.map((k) => k.wire).toSet();
      expect(
        kinds,
        containsAll(<String>[
          'channel.joined',
          'channel.left',
          'channel.error',
          'membership.changed',
          'auth.failed',
          'authz.failed',
          'limit.exceeded',
          'protocol.error',
          'update.rejected',
        ]),
      );
    });

    test('a failed sign-in records that it happened, not who', () {
      // Somebody mistyping their password is the common case. A log naming
      // them leaks a real account name to whoever reads it.
      log()
        ..record(
          SecurityEventKind.authenticationFailed,
          facts: {'code': 'invalid_credentials'},
        )
        ..flush();
      final event = decoded(0);
      expect(event['code'], 'invalid_credentials');
      expect(event.containsKey('username'), isFalse);
    });

    test('a membership change records the change, not the document', () {
      log()
        ..record(
          SecurityEventKind.membershipChanged,
          facts: {
            'kb_id': 'kb-1',
            'change': 'invitation_accepted',
            'member_id': 'u-2',
          },
        )
        ..flush();
      expect(decoded(0)['change'], 'invitation_accepted');
      expect(decoded(0)['kb_id'], 'kb-1');
    });
  });

  group('the file sink', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('ds-seclog'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('appends lines and rotates at the size limit', () {
      final file = File('${dir.path}/security.log');
      final fileSink = SecurityLogFileSink(file, maxBytes: 200);
      for (var i = 0; i < 40; i++) {
        fileSink.write('{"kind":"protocol.error","seq":$i}');
      }
      expect(file.existsSync(), isTrue);
      expect(file.lengthSync(), lessThanOrEqualTo(200 + 64));
      expect(File('${file.path}.1').existsSync(), isTrue);
    });

    test('being refused repeatedly cannot fill the disk', () {
      final file = File('${dir.path}/security.log');
      final fileSink = SecurityLogFileSink(file, maxBytes: 1024);
      for (var i = 0; i < 5000; i++) {
        fileSink.write('{"kind":"limit.exceeded","seq":$i}');
      }
      final total =
          file.lengthSync() + File('${file.path}.1').lengthSync();
      expect(total, lessThan(1024 * 3));
    });

    test('an unwritable path does not throw', () {
      final sink = SecurityLogFileSink(
        File('${dir.path}/nope/../../../../root/denied/security.log'),
      );
      expect(() => sink.write('{"kind":"channel.joined"}'), returnsNormally);
    });
  });
}
