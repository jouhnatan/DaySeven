/// Device-local storage for the policy signing seed.
///
/// A username is only the stable lookup key. It is never mixed into key
/// generation: [policyGenerateKeypair] uses OS entropy, and only the public
/// half may leave this device.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:dayseven/shared/auth/auth_repository.dart';
import 'package:dayseven/shared/crdt/generated/api/policy.dart';

const String _secureKeyPrefix = 'dayseven.policy-signing.v1.';
const String _fallbackDirectoryName = 'policy-signing-keys';

class PolicyKeyStoreException implements Exception {
  const PolicyKeyStoreException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Small seam around the platform plugin so the fallback and read-back checks
/// can be tested without asking a test runner for a real Keychain.
abstract interface class PolicySecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

class FlutterPolicySecureStorage implements PolicySecureStorage {
  FlutterPolicySecureStorage([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
}

typedef ApplicationSupportDirectory = Future<Directory> Function();
typedef RestrictPolicyKeyPath = Future<void> Function(
  String path, {
  required bool directory,
});

/// Stores one Ed25519 seed per device-user.
///
/// Secure platform storage is attempted first and verified by reading the
/// value back. Some Keychain configurations report a successful write but
/// later return null; treating that as success would silently strand the
/// signer. When secure storage is unavailable, the fallback lives below the
/// per-user application support directory with a 0700 directory and 0600 file
/// on Unix, or an inheritance-free current-user ACL on Windows.
class PolicyKeyStore {
  PolicyKeyStore({
    PolicySecureStorage? secureStorage,
    ApplicationSupportDirectory? applicationSupportDirectory,
    RestrictPolicyKeyPath? restrictPath,
  }) : _secureStorage = secureStorage ?? FlutterPolicySecureStorage(),
       _applicationSupportDirectory =
           applicationSupportDirectory ?? _defaultApplicationSupportDirectory,
       _restrictPath = restrictPath ?? _restrictPolicyKeyPath;

  final PolicySecureStorage _secureStorage;
  final ApplicationSupportDirectory _applicationSupportDirectory;
  final RestrictPolicyKeyPath _restrictPath;
  final Map<String, Future<PolicyKeypair>> _activeCreations = {};

  /// Returns the locally held seed, or null on a fresh install/device-user.
  Future<Uint8List?> read(String username) async {
    final index = _validatedIndex(username);
    final secure = await _readSecure(index);
    if (secure != null) return secure;
    return _readFallback(index);
  }

  /// Loads the existing seed or creates exactly one from OS entropy.
  ///
  /// Concurrent Knowledge Base binds for the same account share the same
  /// creation future, so they cannot generate competing device-user keys.
  Future<PolicyKeypair> loadOrCreate(String username) {
    final index = _validatedIndex(username);
    final active = _activeCreations[index];
    if (active != null) return active;

    late final Future<PolicyKeypair> creation;
    creation = _loadOrCreate(index).then(
      (keypair) {
        if (identical(_activeCreations[index], creation)) {
          _activeCreations.remove(index);
        }
        return keypair;
      },
      onError: (Object error, StackTrace stack) {
        if (identical(_activeCreations[index], creation)) {
          _activeCreations.remove(index);
        }
        Error.throwWithStackTrace(error, stack);
      },
    );
    _activeCreations[index] = creation;
    return creation;
  }

  Future<PolicyKeypair> _loadOrCreate(String index) async {
    final existing = await read(index);
    if (existing != null) {
      return PolicyKeypair(
        secretKey: existing,
        publicKey: await policyPublicKey(secretKey: existing),
      );
    }

    final generated = await policyGenerateKeypair();
    await _store(index, generated.secretKey);
    return generated;
  }

  Future<void> _store(String index, Uint8List secret) async {
    final encoded = base64Encode(secret);
    try {
      await _secureStorage.write(_secureKey(index), encoded);
      final readBack = await _secureStorage.read(_secureKey(index));
      if (_decodeSecret(readBack) case final stored?
          when _sameBytes(stored, secret)) {
        return;
      }
    } on Object {
      // A locked, missing, or unsupported Keychain falls through to the
      // restrictive file. The error is deliberately not logged: plugin error
      // strings can contain storage keys, which include the username index.
    }
    await _writeFallback(index, encoded);
  }

  Future<Uint8List?> _readSecure(String index) async {
    try {
      return _decodeSecret(await _secureStorage.read(_secureKey(index)));
    } on Object {
      return null;
    }
  }

  Future<Uint8List?> _readFallback(String index) async {
    final file = await _fallbackFile(index);
    if (!await file.exists()) return null;
    try {
      return _decodeSecret(await file.readAsString());
    } on Object {
      return null;
    }
  }

  Future<void> _writeFallback(String index, String encoded) async {
    final file = await _fallbackFile(index);
    await file.parent.create(recursive: true);
    await _restrictPath(file.parent.path, directory: true);
    try {
      await file.writeAsString(encoded, flush: true);
      await _restrictPath(file.path, directory: false);
    } on Object {
      // Never knowingly leave a seed behind with permissions we could not
      // restrict. This file was created solely by this attempt.
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<File> _fallbackFile(String index) async {
    final support = await _applicationSupportDirectory();
    return File(p.join(support.path, _fallbackDirectoryName, '$index.key'));
  }

  static String _validatedIndex(String username) {
    final normalized = normalizeUsername(username);
    if (usernameProblem(normalized) != null) {
      throw const PolicyKeyStoreException(
        'The signed-in profile has no valid username for policy key storage.',
      );
    }
    return normalized;
  }

  static String _secureKey(String index) => '$_secureKeyPrefix$index';

  static Uint8List? _decodeSecret(String? encoded) {
    if (encoded == null) return null;
    try {
      final bytes = base64Decode(encoded.trim());
      return bytes.length == 32 ? bytes : null;
    } on FormatException {
      return null;
    }
  }

  static bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }

  static Future<Directory> _defaultApplicationSupportDirectory() async =>
      getApplicationSupportDirectory();
}

Future<void> _restrictPolicyKeyPath(
  String path, {
  required bool directory,
}) async {
  late final ProcessResult result;
  if (Platform.isMacOS || Platform.isLinux) {
    result = await Process.run('chmod', [directory ? '700' : '600', path]);
  } else if (Platform.isWindows) {
    final username = Platform.environment['USERNAME'];
    final domain = Platform.environment['USERDOMAIN'];
    if (username == null || username.isEmpty) {
      throw const PolicyKeyStoreException(
        'Windows did not expose the current account for the policy key ACL.',
      );
    }
    final account = domain == null || domain.isEmpty
        ? username
        : '$domain\\$username';
    result = await Process.run('icacls', [
      path,
      '/inheritance:r',
      '/grant:r',
      '$account:(F)',
    ]);
  } else {
    throw const PolicyKeyStoreException(
      'No restrictive policy key storage is available on this platform.',
    );
  }

  if (result.exitCode != 0) {
    throw const PolicyKeyStoreException(
      'Could not restrict the fallback policy key permissions.',
    );
  }
}
