/// The installation's security log, as a provider.
///
/// One log for the whole app rather than one per Knowledge Base: the events
/// worth recording — who signed in, who joined a channel, whose message was
/// refused — cross Knowledge Bases, and reading a scattered set of files after
/// the fact is how an audit trail stops being one.
///
/// The class itself lives in `shared/security/`. This is only where it is
/// given a file and made reachable, because `shared/` may not import `app/`.
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:dayseven/shared/platform/app_profile.dart';
import 'package:dayseven/shared/security/security_log.dart';

const String kSecurityLogFileName = 'security.log';

/// Resolves once, at startup. Falls back to discarding rather than failing:
/// nowhere to write is not a reason to stop the app, and a log that takes the
/// application down with it is worse than no log.
final securityLogProvider = FutureProvider<SecurityLog>((ref) async {
  try {
    final profile = ref.watch(appProfileProvider);
    final dir = profile?.directory ?? await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    return SecurityLog(
      sink: SecurityLogFileSink(File(p.join(dir.path, kSecurityLogFileName))),
    );
  } on Object {
    return SecurityLog(sink: const NullSecuritySink());
  }
});

/// The synchronous view, for call sites that cannot await.
///
/// Discards until the file is resolved, which is a few milliseconds at
/// startup. Losing an event from that window is preferable to making every
/// caller asynchronous for the sake of it.
final securityLogSyncProvider = Provider<SecurityLog>((ref) {
  return ref.watch(securityLogProvider).maybeWhen(
    data: (log) => log,
    orElse: () => SecurityLog(sink: const NullSecuritySink()),
  );
});

/// Records a failed sign-in.
///
/// The username is deliberately *not* recorded. Somebody mistyping their
/// password repeatedly is the common case, and a log naming them is a log that
/// leaks a real account name to anyone who reads it. What matters for an audit
/// is that failures happened, how many, and when.
void recordAuthenticationFailure(SecurityLog log, {String? code}) {
  log.record(SecurityEventKind.authenticationFailed, facts: {'code': code});
}

void recordMembershipChange(
  SecurityLog log, {
  required String kbId,
  required String change,
  String? memberId,
  String? role,
}) {
  log.record(
    SecurityEventKind.membershipChanged,
    facts: {
      'kb_id': kbId,
      'change': change,
      'member_id': memberId,
      'role': role,
    },
  );
}
