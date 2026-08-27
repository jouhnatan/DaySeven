/// Which policy a client runs with, and where it came from.
///
/// The case that motivated this file: an owner signs a policy, and their
/// friend — a member who cannot sign anything — opens the same Knowledge Base
/// on another machine. `metadata/` never travels, so that friend has no
/// `policy.json` and no way to make one. If nothing is published for them to
/// verify, they are stuck out of collaboration permanently, and no amount of
/// republishing on the owner's machine changes it.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/generated/api/policy.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/policy_bootstrap.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _otherKb = '01a01830-9749-7398-9626-dab25d46040f';
const _owner = 'user-owner';
const _friend = 'user-friend';
const _protectedFile = 'file-protected';

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

WorkspacePolicy _snapshot({
  String kbId = _kb,
  Map<String, PolicyRole> members = const {
    _owner: PolicyRole.owner,
    _friend: PolicyRole.editor,
  },
}) => WorkspacePolicy(
  kbId: kbId,
  ownerId: _owner,
  issuedAt: DateTime.utc(2026, 8, 26),
  members: members,
  protectedFiles: const {
    _protectedFile: ProtectedFile(
      fileId: _protectedFile,
      minimumPublishRole: PolicyRole.owner,
    ),
  },
);

void main() {
  final path = _libraryPath();

  group('policy bootstrap', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    late PolicyKeypair ownerKeys;
    late String signed;
    setUp(() async {
      ownerKeys = await policyGenerateKeypair();
      signed = await _snapshot().signedJson(ownerKeys.secretKey);
    });

    Future<PolicyPlan> resolveFor({
      required bool maySign,
      required bool keyMatches,
      Uint8List? publishedKey,
      String? publishedDocument,
      String? localDocument,
      WorkspacePolicy? snapshot,
    }) => resolvePolicy(
      kbId: _kb,
      snapshot: snapshot ?? _snapshot(),
      publishedKey: publishedKey,
      publishedDocument: publishedDocument,
      localDocument: localDocument,
      maySign: maySign,
      keyMatches: keyMatches,
    );

    group('a member who cannot sign', () {
      test('adopts the published policy when it has no local copy', () async {
        final plan = await resolveFor(
          maySign: false,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
          publishedDocument: signed,
        );

        // The regression this file exists for. Without a published copy this
        // member has no policy, no way to make one, and no way out.
        expect(plan, isA<PolicyReady>());
        final ready = plan as PolicyReady;
        expect(ready.policy.roleOf(_friend), PolicyRole.editor);
        expect(ready.documentToCache, signed, reason: 'cached for offline');
        expect(ready.needsRepublish, isNull);
      });

      test('is blocked when a key is published but no policy is', () async {
        final plan = await resolveFor(
          maySign: false,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
        );

        expect(plan, isA<PolicyBlocked>());
        final blocked = plan as PolicyBlocked;
        expect(blocked.thisDeviceCanFixIt, isFalse);
        expect(blocked.message, contains('Ask an owner or co-owner'));
      });

      test('refuses a published policy signed by a different key', () async {
        final impostor = await policyGenerateKeypair();
        final forged = await _snapshot(
          members: const {_owner: PolicyRole.owner, _friend: PolicyRole.owner},
        ).signedJson(impostor.secretKey);

        final plan = await resolveFor(
          maySign: false,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
          publishedDocument: forged,
        );

        expect(plan, isA<PolicyBlocked>());
        expect(
          (plan as PolicyBlocked).message,
          contains('cannot be verified'),
          reason: 'a tampered row must not read as an absent one',
        );
      });

      test('refuses a published policy for another Knowledge Base', () async {
        final elsewhere = await _snapshot(
          kbId: _otherKb,
        ).signedJson(ownerKeys.secretKey);

        final plan = await resolveFor(
          maySign: false,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
          publishedDocument: elsewhere,
        );

        expect(plan, isA<PolicyBlocked>());
      });

      test('prefers its own verified file over the published copy', () async {
        final plan = await resolveFor(
          maySign: false,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
          publishedDocument: signed,
          localDocument: signed,
        );

        expect((plan as PolicyReady).documentToCache, isNull);
      });

      test('has no policy when nothing has ever been signed', () async {
        expect(
          await resolveFor(maySign: false, keyMatches: false),
          isA<PolicyAbsent>(),
        );
      });
    });

    group('a member who can sign', () {
      test('publishes when the Knowledge Base has no key yet', () async {
        expect(
          await resolveFor(maySign: true, keyMatches: false),
          isA<PolicyNeedsPublishing>(),
        );
      });

      test('publishes when its own file is current but nothing is '
          'published', () async {
        // The owner's machine looked healthy throughout the outage: its file
        // verified against its own key, so nothing prompted a republish while
        // the other member had nothing at all.
        expect(
          await resolveFor(
            maySign: true,
            keyMatches: true,
            publishedKey: ownerKeys.publicKey,
            localDocument: signed,
          ),
          isA<PolicyNeedsPublishing>(),
        );
      });

      test('re-signs when membership has changed since', () async {
        final grown = _snapshot(
          members: const {
            _owner: PolicyRole.owner,
            _friend: PolicyRole.coOwner,
          },
        );

        expect(
          await resolveFor(
            maySign: true,
            keyMatches: true,
            publishedKey: ownerKeys.publicKey,
            publishedDocument: signed,
            localDocument: signed,
            snapshot: grown,
          ),
          isA<PolicyNeedsPublishing>(),
        );
      });

      test('leaves a current policy alone', () async {
        final plan = await resolveFor(
          maySign: true,
          keyMatches: true,
          publishedKey: ownerKeys.publicKey,
          publishedDocument: signed,
          localDocument: signed,
        );

        expect(plan, isA<PolicyReady>());
        expect((plan as PolicyReady).needsRepublish, isNull);
      });

      test('runs on a second device without the key, and says so', () async {
        // An owner on a fresh install can still collaborate under the policy
        // somebody else signed; what it cannot do is change it silently.
        final plan = await resolveFor(
          maySign: true,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
          publishedDocument: signed,
        );

        expect(plan, isA<PolicyReady>());
        expect((plan as PolicyReady).needsRepublish, isNotNull);
      });

      test('is offered the repair when nothing verifies', () async {
        final plan = await resolveFor(
          maySign: true,
          keyMatches: false,
          publishedKey: ownerKeys.publicKey,
          localDocument: '{"policy":{},"signature":"nonsense"}',
        );

        expect(plan, isA<PolicyBlocked>());
        expect((plan as PolicyBlocked).thisDeviceCanFixIt, isTrue);
        expect(plan.message, contains('Republish'));
      });
    });
  }, skip: path == null ? 'the yrs dylib is not built' : null);
}
