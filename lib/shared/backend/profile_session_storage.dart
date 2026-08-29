/// Per-profile Supabase session storage.
///
/// The library's default keeps the session in SharedPreferences, which on
/// macOS is one `NSUserDefaults` domain for the whole application. Every
/// running copy therefore reads and writes the same login, which is precisely
/// what stops a second window from holding a second account.
///
/// Pointing [LocalStorage] at a file inside a profile directory gives each
/// instance its own session. Only non-primary profiles use these: the primary
/// keeps the library default so existing installations stay signed in on the
/// exact code path they already use.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

/// A session persisted as a single file.
class FileLocalStorage extends LocalStorage {
  FileLocalStorage(this.file);

  /// The session for the profile rooted at [directory].
  factory FileLocalStorage.inDirectory(Directory directory) =>
      FileLocalStorage(File(p.join(directory.path, 'supabase_session.json')));

  final File file;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> hasAccessToken() => file.exists();

  @override
  Future<String?> accessToken() async {
    if (!await file.exists()) return null;
    try {
      return await file.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> removePersistedSession() async {
    try {
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // A session we cannot delete is not worth failing sign-out over.
    }
  }

  @override
  Future<void> persistSession(String persistSessionString) async {
    await file.parent.create(recursive: true);
    // Temp and rename: a torn session file reads as a corrupt login rather
    // than an absent one, and the person cannot tell why they were signed out.
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(persistSessionString, flush: true);
    await temporary.rename(file.path);
  }
}

/// PKCE verifiers for one profile, kept beside its session.
///
/// These are short-lived and only matter mid-sign-in, but they must not be
/// shared: two instances signing in at once would overwrite each other's
/// verifier and both exchanges would fail.
class FileGotrueAsyncStorage extends GotrueAsyncStorage {
  FileGotrueAsyncStorage(this.file);

  factory FileGotrueAsyncStorage.inDirectory(Directory directory) =>
      FileGotrueAsyncStorage(File(p.join(directory.path, 'supabase_pkce.json')));

  final File file;

  Future<Map<String, Object?>> _read() async {
    if (!await file.exists()) return {};
    try {
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on Object {
      return {};
    }
  }

  Future<void> _write(Map<String, Object?> data) async {
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsString(jsonEncode(data), flush: true);
    await temporary.rename(file.path);
  }

  @override
  Future<String?> getItem({required String key}) async =>
      (await _read())[key] as String?;

  @override
  Future<void> setItem({required String key, required String value}) async {
    final data = await _read();
    data[key] = value;
    await _write(data);
  }

  @override
  Future<void> removeItem({required String key}) async {
    final data = await _read();
    if (data.remove(key) == null) return;
    await _write(data);
  }
}
