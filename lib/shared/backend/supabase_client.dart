/// The Supabase client and the error vocabulary that goes with it.
///
/// Every feature that talks to the server needs the client and a way to render
/// a failure; none of them needs another feature's repository. Keeping this
/// plumbing separate is what lets the repositories live beside the features
/// that own them.
library;

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

/// Supplied at build time with `--dart-define-from-file=env/supabase.json`.
const String kSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String kSupabasePublishableKey = String.fromEnvironment(
  'SUPABASE_PUBLISHABLE_KEY',
);

/// Just above the server's `statement_timeout`, which is 8s for the
/// `authenticated` role (verified on the live project, 2026-08-26).
///
/// The order matters. If the client gives up first it abandons a query the
/// server is still running, learns nothing about why, and — with a blind retry
/// behind it — starts another. Waiting slightly longer than the server means a
/// slow query comes back as a real error with a real message, and only a
/// genuinely unresponsive network hits this ceiling. The previous 15s left a
/// seven-second window where the request was already dead and the client was
/// still holding it open.
const Duration kSupabaseRequestTimeout = Duration(seconds: 10);

/// Storage does not inherit PostgREST's request timeout. Give image transfers
/// enough time for an ordinary connection while still returning control to the
/// person who pressed Share or Sync when a socket stops making progress.
const Duration kSupabaseStorageRequestTimeout = Duration(seconds: 30);

/// True when the app was built with Supabase credentials. Without them the
/// application still runs entirely locally — a Knowledge Base is a folder, and
/// only collaboration needs the network.
bool get isSupabaseConfigured =>
    kSupabaseUrl.isNotEmpty && kSupabasePublishableKey.isNotEmpty;

/// [auth] carries the profile's session storage. The default leaves it to the
/// library, which is what an ordinary single-window installation wants.
Future<void> initSupabase({
  FlutterAuthClientOptions auth = const FlutterAuthClientOptions(),
}) async {
  if (!isSupabaseConfigured) return;
  await Supabase.initialize(
    url: kSupabaseUrl,
    publishableKey: kSupabasePublishableKey,
    authOptions: auth,
    postgrestOptions: const PostgrestClientOptions(
      // Deliberately no transport-level retry.
      //
      // A blind retry does not know what it is resending. During the
      // 2026-08-25 outage three endpoints retried in lockstep every 2-3
      // seconds, which is how a slow instance became an unavailable one:
      // every retry added load to the thing that was already failing, and
      // arrived at the same moment as everyone else's.
      //
      // Retrying is now the caller's decision, taken where the caller knows
      // whether the request can succeed at all — `RetryBudget`, which backs
      // off exponentially, jitters so peers do not synchronise, and gives up
      // rather than resending forever.
      retryCount: 0,
      requestTimeout: kSupabaseRequestTimeout,
    ),
  );
}

SupabaseClient get supabase => Supabase.instance.client;

/// Renders an error as something worth pasting: the message plus whatever
/// codes the failure carries, rather than just a class name.
String describeError(Object error) {
  if (error is AuthException) {
    final parts = <String>[
      error.message,
      if (error.statusCode != null) 'status ${error.statusCode}',
      if (error.code != null) 'code ${error.code}',
    ];
    final detail = 'Auth: ${parts.join(' · ')}';

    // Two failures here are project settings rather than anything the person
    // typed, and say so in terms of an email they never entered.
    final explanation = switch (error.code) {
      'email_not_confirmed' || 'over_email_send_rate_limit' =>
        'DaySeven accounts are username-only, but this project still has email '
            'confirmation switched on, so signing up tries to send mail. Turn '
            'off Authentication → Sign In / Providers → Email → "Confirm '
            'email" in the Supabase dashboard.',
      _ => null,
    };

    return explanation == null ? detail : '$explanation\n\n$detail';
  }

  if (error is PostgrestException) {
    // `private.publish_gate` answers a looping caller with PT429 rather than
    // doing the work. That is a deliberate refusal, not a fault, and it reads
    // as one.
    if (isRateLimited(error)) {
      return 'Too many rejected publishes in a row, so the server is holding '
          'this document off for a moment. Sync the Knowledge Base to pick up '
          'the newest revision, then publish again.'
          '${error.hint == null ? '' : '\n\n${error.hint}'}';
    }
    // An optimistic-lock conflict is ordinary collaboration: someone else's
    // revision landed first. The raw errcode, details and hint are for the
    // log, not for the person holding the file.
    if (isPublishConflict(error)) {
      return 'A collaborator published a newer revision of this document. '
          'Sync the Knowledge Base to pick it up, then publish again.';
    }
    final parts = <String>[
      error.message,
      if (error.code != null) 'code ${error.code}',
      if (error.details != null) 'details ${error.details}',
      if (error.hint != null) 'hint ${error.hint}',
    ];
    return 'Database: ${parts.join(' · ')}';
  }

  if (error is StorageException) {
    return 'Storage: ${error.message}'
        '${error.statusCode == null ? '' : ' · status ${error.statusCode}'}';
  }

  if (error is TimeoutException) {
    return 'The server did not respond in time. Try again.';
  }

  if (error is SocketException) {
    return 'The server could not be reached. Check the connection and try '
        'again.';
  }

  if (error is SyncException) return error.message;

  return '$error';
}

/// The server refused a request because the caller was repeating it. Distinct
/// from an optimistic-lock conflict: a conflict is worth one considered retry
/// against fresh state, this is worth none at all.
bool isRateLimited(Object error) =>
    error is PostgrestException && error.code == 'PT429';

/// The canonical document moved past the revision this call was written
/// against. Worth one considered retry from fresh state, and worth counting as
/// a conflict rather than aborting a whole sync when it happens mid-loop.
bool isPublishConflict(Object error) =>
    error is PostgrestException && error.code == '40001';

class SyncException implements Exception {
  const SyncException(this.message);
  final String message;

  @override
  String toString() => message;
}
