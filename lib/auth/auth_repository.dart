/// Who is signed in.
///
/// Accounts are username and password. Supabase Auth signs in with an email, so
/// a username maps to a synthetic address the user never sees and nothing is
/// ever sent to.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:dayseven/sync/supabase.dart';

final authStateProvider = StreamProvider<AuthState?>((ref) {
  if (!isSupabaseConfigured) return const Stream.empty();
  return supabase.auth.onAuthStateChange;
});

/// The signed-in user, or null when working offline.
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return isSupabaseConfigured ? supabase.auth.currentUser : null;
});

class Profile {
  const Profile({
    required this.id,
    required this.username,
    required this.displayName,
  });

  final String id;

  /// What the person signs in with, and what a collaborator invites them by.
  final String username;

  /// The name the user chose for themselves, shown to collaborators.
  final String displayName;
}

/// The domain the synthetic addresses are built on.
///
/// Not `.local`: Supabase Auth validates the address on sign-up and rejects
/// domains it considers unroutable, so `name@dayseven.local` fails with
/// "Email address is invalid" before an account is ever created. This has to be
/// a domain with a real TLD.
///
/// Nothing is sent here — but that depends on email confirmation being off in
/// the project's auth settings. If confirmations are ever turned on, this must
/// become a domain you actually control.
const String kAccountEmailDomain = 'dayseven.app';

/// Accounts are username-based. Supabase Auth signs in with an email, so each
/// username maps to a synthetic address the user never sees.
String syntheticEmailFor(String username) =>
    '${normalizeUsername(username)}@$kAccountEmailDomain';

String normalizeUsername(String username) => username.trim().toLowerCase();

/// The rule the database enforces, checked here so the message is a sentence
/// rather than a constraint violation.
String? usernameProblem(String username) {
  final value = normalizeUsername(username);
  if (value.isEmpty) return 'Choose a username.';
  if (!RegExp(r'^[a-z0-9_-]{3,32}$').hasMatch(value)) {
    return 'A username is 3-32 characters of a-z, 0-9, _ or -';
  }
  return null;
}

class AuthRepository {
  Future<void> signIn(String username, String password) =>
      supabase.auth.signInWithPassword(
        email: syntheticEmailFor(username),
        password: password,
      );

  Future<void> signUp(String username, String password, String displayName) {
    final problem = usernameProblem(username);
    if (problem != null) throw SyncException(problem);

    final normalized = normalizeUsername(username);
    return supabase.auth.signUp(
      email: syntheticEmailFor(normalized),
      password: password,
      data: {
        'username': normalized,
        'display_name': displayName.trim().isEmpty
            ? normalized
            : displayName.trim(),
      },
    );
  }

  Future<void> signOut() => supabase.auth.signOut();

  Future<Profile?> myProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return null;
    final row = await supabase
        .from('profiles')
        .select('id, username, display_name')
        .eq('id', user.id)
        .maybeSingle();
    if (row == null) return null;
    return Profile(
      id: row['id'] as String,
      username: row['username'] as String,
      displayName: row['display_name'] as String,
    );
  }

  /// Changing the display name changes what collaborators see on every
  /// proposal, including ones already sent.
  Future<void> setDisplayName(String displayName) async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    await supabase
        .from('profiles')
        .update({'display_name': displayName})
        .eq('id', user.id);
  }
}

final authRepositoryProvider = Provider((ref) => AuthRepository());

final myProfileProvider = FutureProvider<Profile?>((ref) {
  ref.watch(authStateProvider);
  if (!isSupabaseConfigured) return Future.value(null);
  return ref.read(authRepositoryProvider).myProfile();
});
