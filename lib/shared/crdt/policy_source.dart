/// Which protection rules a client should run with, and where they came from.
///
/// Postgres is the authority. A client that reached it runs with what it said
/// and writes a cache; a client that could not falls back to that cache; a
/// client with neither does not collaborate at all.
///
/// That last case is the one worth stating plainly. "The rules could not be
/// read" and "there are no rules" are different facts, and treating the first
/// as the second is how a protected file gets edited directly by somebody who
/// was never allowed to. So an unknown policy stops collaboration rather than
/// defaulting to the permissive answer.
///
/// Kept pure and separate from the controller so the awkward combinations can
/// be tested directly rather than only in front of two real machines.
library;

import 'package:dayseven/shared/crdt/workspace_policy.dart';

/// What the caller should do about the policy.
sealed class PolicySource {
  const PolicySource();
}

/// The authority answered. Run with [policy] and write [documentToCache] so
/// this member can keep working the next time it cannot be reached.
class PolicyFromAuthority extends PolicySource {
  const PolicyFromAuthority(this.policy, this.documentToCache);

  final WorkspacePolicy policy;
  final String documentToCache;
}

/// The authority could not be reached, but a usable cache was on disk.
class PolicyFromCache extends PolicySource {
  const PolicyFromCache(this.policy);

  final WorkspacePolicy policy;
}

/// Nothing trustworthy is available. Collaboration must not start.
class PolicyUnavailable extends PolicySource {
  const PolicyUnavailable(this.message);

  final String message;
}

/// Works out the plan.
///
/// [authoritative] is what Postgres said, or null when it could not be read.
/// [cachedDocument] is the contents of `policy.json`, or null when absent.
PolicySource resolvePolicySource({
  required WorkspacePolicy? authoritative,
  required String? cachedDocument,
  required String expectedKbId,
  String? authorityError,
}) {
  if (authoritative != null) {
    return PolicyFromAuthority(authoritative, authoritative.cacheJson());
  }

  if (cachedDocument != null) {
    try {
      return PolicyFromCache(
        WorkspacePolicy.fromCache(cachedDocument, expectedKbId: expectedKbId),
      );
    } on Object {
      // A cache that will not parse is not a cache. Fall through and refuse,
      // rather than run on rules nobody can vouch for.
    }
  }

  return PolicyUnavailable(
    'The protection rules for this Knowledge Base could not be read, and this '
    'device has no usable cached copy. Collaboration will not start until they '
    'are known. Local editing is unaffected.'
    '${authorityError == null ? '' : '\n\n$authorityError'}',
  );
}
