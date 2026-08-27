import 'dart:async';
import 'dart:io';

import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/policy_key_store.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

class MemorySecureStorage implements PolicySecureStorage {
  final Map<String, String> values = {};
  bool unavailable = false;
  bool forgetWrites = false;
  bool hangs = false;

  @override
  Future<String?> read(String key) async {
    if (hangs) return Completer<String?>().future;
    if (unavailable) throw StateError('secure storage unavailable');
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (hangs) return Completer<void>().future;
    if (unavailable) throw StateError('secure storage unavailable');
    if (!forgetWrites) values[key] = value;
  }
}

String? _libraryPath() {
  final root = Directory.current.path;
  for (final candidate in [
    '$root/rust/target/release/libdayseven_crdt.dylib',
    '$root/rust/target/debug/libdayseven_crdt.dylib',
    '$root/rust/target/release/dayseven_crdt.dll',
    '$root/rust/target/release/libdayseven_crdt.so',
  ]) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

void main() {
  late Directory support;

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(_libraryPath()!));
  });

  setUp(() {
    support = Directory.systemTemp.createTempSync('ds-policy-keys');
  });

  tearDown(() {
    support.deleteSync(recursive: true);
  });

  PolicyKeyStore store(
    MemorySecureStorage secure, {
    Duration timeout = kPolicySecureStorageTimeout,
  }) => PolicyKeyStore(
    secureStorage: secure,
    applicationSupportDirectory: () async => support,
    secureStorageTimeout: timeout,
  );

  test(
    'creates one random key and reads it back from secure storage',
    () async {
      final secure = MemorySecureStorage();
      final keys = store(secure);

      final created = await keys.loadOrCreate('aldenmoor_owner');
      final loaded = await keys.loadOrCreate('aldenmoor_owner');

      expect(created.secretKey, loaded.secretKey);
      expect(created.publicKey, loaded.publicKey);
      expect(created.secretKey, hasLength(32));
      expect(secure.values, hasLength(1));
      expect(
        Directory('${support.path}/policy-signing-keys').existsSync(),
        isFalse,
        reason: 'a working Keychain must not also leave a plaintext fallback',
      );
    },
  );

  test('the public username indexes independent random keys', () async {
    final first = await store(MemorySecureStorage()).loadOrCreate('same_user');
    final second = await store(MemorySecureStorage()).loadOrCreate('same_user');

    expect(first.secretKey, isNot(second.secretKey));
    expect(first.publicKey, isNot(second.publicKey));
  });

  test('a phantom secure write falls back and survives reopening', () async {
    final secure = MemorySecureStorage()..forgetWrites = true;
    final firstStore = store(secure);
    final first = await firstStore.loadOrCreate('owner_1');

    final file = File('${support.path}/policy-signing-keys/owner_1.key');
    expect(file.existsSync(), isTrue);
    if (!Platform.isWindows) {
      expect(file.statSync().mode & 0x1ff, 0x180); // 0600
      expect(file.parent.statSync().mode & 0x1ff, 0x1c0); // 0700
    }

    final second = await store(secure).loadOrCreate('owner_1');
    expect(second.secretKey, first.secretKey);
    expect(second.publicKey, first.publicKey);
  });

  test('an unavailable secure store uses the restrictive fallback', () async {
    final secure = MemorySecureStorage()..unavailable = true;
    final keypair = await store(secure).loadOrCreate('owner_2');

    expect(keypair.secretKey, hasLength(32));
    expect(
      File('${support.path}/policy-signing-keys/owner_2.key').existsSync(),
      isTrue,
    );
  });

  test(
    'a secure store that never answers falls back instead of hanging',
    () async {
      final secure = MemorySecureStorage()..hangs = true;
      final keys = store(secure, timeout: const Duration(milliseconds: 10));

      final created = await keys
          .loadOrCreate('owner_3')
          .timeout(const Duration(seconds: 1));
      final loaded = await keys
          .loadOrCreate('owner_3')
          .timeout(const Duration(seconds: 1));

      expect(loaded.secretKey, created.secretKey);
      expect(
        File('${support.path}/policy-signing-keys/owner_3.key').existsSync(),
        isTrue,
      );
    },
  );

  test('refuses an invalid username index', () async {
    expect(
      () => store(MemorySecureStorage()).loadOrCreate('../owner'),
      throwsA(isA<PolicyKeyStoreException>()),
    );
  });
}
