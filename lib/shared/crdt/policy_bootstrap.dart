/// Deciding which signed policy a client should run with, and how it got it.
///
/// A client opening a shared Knowledge Base can be looking at up to three
/// things: a `policy.json` on its own disk, a copy the signer published, and
/// the database's own view of membership and protection. This works out which
/// of them to believe, without touching the network or the filesystem, so the
/// awkward combinations — a stale local file, a published document signed by a
/// key that has since been replaced, an owner on a fresh install — can be
/// tested directly rather than only in front of two real machines.
///
/// **Verification happens here, not before.** Both the local file and the
/// published document arrive from somewhere untrusted, and neither is believed
/// without an Ed25519 signature from the published key over that exact body,
/// naming this exact Knowledge Base.
library;

import 'dart:typed_data';

import 'package:dayseven/shared/crdt/workspace_policy.dart';

/// What the caller should do about the policy.
sealed class PolicyPlan {
  const PolicyPlan();
}

/// The Knowledge Base has no published signing key, and nothing is protected.
class PolicyAbsent extends PolicyPlan {
  const PolicyAbsent();
}

/// Run with [policy].
///
/// [documentToCache] is set when the policy came from the published copy
/// rather than from disk: writing it locally is what lets this member open the
/// workspace again while offline.
class PolicyReady extends PolicyPlan {
  const PolicyReady(this.policy, {this.documentToCache, this.needsRepublish});

  final WorkspacePolicy policy;
  final String? documentToCache;

  /// Set when this account may sign but this device does not hold the key the
  /// published policy was signed with — advisory, not a failure.
  final String? needsRepublish;
}

/// Sign the current snapshot on this device, publish it, and write it out.
///
/// Reached when this device holds the signing key and what is published is
/// missing, stale, or unverifiable.
class PolicyNeedsPublishing extends PolicyPlan {
  const PolicyNeedsPublishing();
}

/// Nothing trustworthy is available. Collaboration must not start.
class PolicyBlocked extends PolicyPlan {
  const PolicyBlocked(this.message, {required this.thisDeviceCanFixIt});

  final String message;

  /// Whether the person looking at this can repair it by republishing, or has
  /// to ask somebody who can sign.
  final bool thisDeviceCanFixIt;
}

/// Works out the plan.
///
/// [snapshot] is the database's own view, which is the enforcement that counts
/// and therefore also what a signer signs. [maySign] is whether this account
/// holds a role permitted to sign; [keyMatches] whether this device's stored
/// secret matches [publishedKey].
Future<PolicyPlan> resolvePolicy({
  required String kbId,
  required WorkspacePolicy snapshot,
  required Uint8List? publishedKey,
  required String? publishedDocument,
  required String? localDocument,
  required bool maySign,
  required bool keyMatches,
}) async {
  if (publishedKey == null) {
    if (maySign) return const PolicyNeedsPublishing();
    if (localDocument != null) {
      // A file signed by a key nobody published cannot be checked at all, and
      // running as though there were no policy would quietly ignore whatever
      // it protects.
      return const PolicyBlocked(
        'This Knowledge Base has a policy file but no published signing key. '
        'Ask an owner or co-owner to republish the policy.',
        thisDeviceCanFixIt: false,
      );
    }
    return const PolicyAbsent();
  }

  final local = await _verify(localDocument, publishedKey, kbId);
  final published = await _verify(publishedDocument, publishedKey, kbId);

  if (maySign && keyMatches) {
    // The published copy is what every other member reads. It being stale is
    // as much a reason to re-sign as the local file being stale, and it is the
    // one nobody else can repair.
    final currentHere = local.policy?.hasSameRulesAs(snapshot) ?? false;
    final currentThere = published.policy?.hasSameRulesAs(snapshot) ?? false;
    if (!currentHere || !currentThere) {
      return const PolicyNeedsPublishing();
    }
    return PolicyReady(local.policy!);
  }

  const republishHint =
      'This device does not hold the key matching the published policy. '
      'Republish before changing membership or protection.';

  if (local.policy case final policy?) {
    return PolicyReady(policy, needsRepublish: maySign ? republishHint : null);
  }
  if (published.policy case final policy?) {
    return PolicyReady(
      policy,
      documentToCache: publishedDocument,
      needsRepublish: maySign ? republishHint : null,
    );
  }

  return PolicyBlocked(
    '${_reason(local, published)} '
    '${maySign ? 'Republish the policy from this device to create a new trusted signing root.' : 'Ask an owner or co-owner to republish it.'}',
    thisDeviceCanFixIt: maySign,
  );
}

/// Why nothing could be believed, in the order that is most useful to hear.
///
/// A document that failed verification is a different sentence from one that
/// was never there, and saying "missing" about a file somebody tampered with
/// would send the reader looking for the wrong problem.
String _reason(_Checked local, _Checked published) {
  if (local.error != null) return 'The signed policy file cannot be verified.';
  if (published.error != null) {
    return 'The published policy cannot be verified against this Knowledge '
        "Base's signing key.";
  }
  return 'The signed policy file is missing, and no policy has been published '
      'for this Knowledge Base.';
}

class _Checked {
  const _Checked(this.policy, this.error);
  final WorkspacePolicy? policy;
  final Object? error;
}

Future<_Checked> _verify(
  String? document,
  Uint8List key,
  String kbId,
) async {
  if (document == null) return const _Checked(null, null);
  try {
    return _Checked(
      await WorkspacePolicy.verified(
        document,
        ownerPublicKey: key,
        expectedKbId: kbId,
      ),
      null,
    );
  } on Object catch (error) {
    return _Checked(null, error);
  }
}
