/// The signed ownership policy, and the attacks it exists to stop.
///
/// A policy is a file that tells a client who is allowed to write. It travels
/// with the workspace, so every one of these tests is really the same
/// question: what happens when the file is not what the owner wrote?
library;

import 'dart:convert';
import 'dart:io';

import 'package:dayseven/shared/crdt/generated/api/policy.dart';
import 'package:dayseven/shared/crdt/generated/frb_generated.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart'
    show ExternalLibrary;
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _owner = 'user-owner';
const _editor = 'user-editor';
const _reviewer = 'user-reviewer';
const _protectedFile = 'file-protected';
const _openFile = 'file-open';

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

WorkspacePolicy policy({String kbId = _kb}) => WorkspacePolicy(
  kbId: kbId,
  ownerId: _owner,
  issuedAt: DateTime.utc(2026, 8, 26),
  members: const {
    _owner: PolicyRole.owner,
    _editor: PolicyRole.editor,
    _reviewer: PolicyRole.reviewer,
  },
  protectedFiles: const {
    _protectedFile: ProtectedFile(
      fileId: _protectedFile,
      minimumPublishRole: PolicyRole.owner,
    ),
  },
);

void main() {
  final path = _libraryPath();

  group('workspace policy', () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(path!));
    });

    late PolicyKeypair ownerKeys;
    setUp(() async => ownerKeys = await policyGenerateKeypair());

    group('permissions as written', () {
      test('an editor may write an unprotected file', () {
        expect(
          policy().canWriteDirectly(userId: _editor, fileId: _openFile),
          isTrue,
        );
      });

      test('an editor may not write an owner-protected file', () {
        expect(
          policy().canWriteDirectly(userId: _editor, fileId: _protectedFile),
          isFalse,
        );
      });

      test('the owner may write anything', () {
        expect(
          policy().canWriteDirectly(userId: _owner, fileId: _protectedFile),
          isTrue,
        );
      });

      test('a reviewer may write nothing at all', () {
        for (final file in [_openFile, _protectedFile]) {
          expect(
            policy().canWriteDirectly(userId: _reviewer, fileId: file),
            isFalse,
            reason: file,
          );
        }
      });

      test('somebody the policy has never heard of may write nothing', () {
        expect(
          policy().canWriteDirectly(userId: 'stranger', fileId: _openFile),
          isFalse,
        );
      });
    });

    group('signing', () {
      test('a policy the owner signed verifies', () async {
        final signed = await policy().signedJson(ownerKeys.secretKey);
        final verified = await WorkspacePolicy.verified(
          signed,
          ownerPublicKey: ownerKeys.publicKey,
          expectedKbId: _kb,
        );
        expect(verified.ownerId, _owner);
        expect(verified.members[_editor], PolicyRole.editor);
        expect(verified.isProtected(_protectedFile), isTrue);
      });

      test(
        'canonical bytes are stable regardless of map insertion order',
        () async {
          // Two clients must agree byte-for-byte on what was signed, or a
          // signature stops verifying for reasons nobody can see.
          final a = WorkspacePolicy(
            kbId: _kb,
            ownerId: _owner,
            issuedAt: DateTime.utc(2026, 8, 26),
            members: const {
              _owner: PolicyRole.owner,
              _editor: PolicyRole.editor,
            },
            protectedFiles: const {},
          );
          final b = WorkspacePolicy(
            kbId: _kb,
            ownerId: _owner,
            issuedAt: DateTime.utc(2026, 8, 26),
            members: const {
              _editor: PolicyRole.editor,
              _owner: PolicyRole.owner,
            },
            protectedFiles: const {},
          );
          expect(a.canonicalBytes(), b.canonicalBytes());
        },
      );

      test(
        'rule comparison ignores issue time but catches permission changes',
        () {
          final sameRulesLater = WorkspacePolicy(
            kbId: _kb,
            ownerId: _owner,
            issuedAt: DateTime.utc(2030),
            members: policy().members,
            protectedFiles: policy().protectedFiles,
          );
          final promotedEditor = WorkspacePolicy(
            kbId: _kb,
            ownerId: _owner,
            issuedAt: DateTime.utc(2030),
            members: const {
              _owner: PolicyRole.owner,
              _editor: PolicyRole.coOwner,
              _reviewer: PolicyRole.reviewer,
            },
            protectedFiles: policy().protectedFiles,
          );

          expect(policy().hasSameRulesAs(sameRulesLater), isTrue);
          expect(policy().hasSameRulesAs(promotedEditor), isFalse);
        },
      );

      test('promoting yourself in the file breaks the signature', () async {
        // The attack: edit policy.json to make yourself an owner, leave the
        // signature alone, hope nobody checks.
        final signed = await policy().signedJson(ownerKeys.secretKey);
        final tampered = jsonDecode(signed) as Map<String, Object?>;
        final body = tampered['policy'] as Map<String, Object?>;
        body['members'] = [
          {'user_id': _editor, 'role': 'owner'},
        ];

        await expectLater(
          WorkspacePolicy.verified(
            jsonEncode(tampered),
            ownerPublicKey: ownerKeys.publicKey,
            expectedKbId: _kb,
          ),
          throwsA(
            isA<WorkspacePolicyException>().having(
              (e) => e.message,
              'message',
              contains('does not match its signature'),
            ),
          ),
        );
      });

      test('unprotecting a file breaks the signature', () async {
        final signed = await policy().signedJson(ownerKeys.secretKey);
        final tampered = jsonDecode(signed) as Map<String, Object?>;
        (tampered['policy'] as Map<String, Object?>)['protected_files'] =
            <Object>[];
        await expectLater(
          WorkspacePolicy.verified(
            jsonEncode(tampered),
            ownerPublicKey: ownerKeys.publicKey,
            expectedKbId: _kb,
          ),
          throwsA(isA<WorkspacePolicyException>()),
        );
      });

      test('a policy signed by somebody else does not verify', () async {
        final mallory = await policyGenerateKeypair();
        final forged = await policy().signedJson(mallory.secretKey);
        await expectLater(
          WorkspacePolicy.verified(
            forged,
            ownerPublicKey: ownerKeys.publicKey,
            expectedKbId: _kb,
          ),
          throwsA(isA<WorkspacePolicyException>()),
        );
      });

      test(
        'a validly signed policy for another Knowledge Base is refused',
        () async {
          // Copy a folder's policy into a different workspace and inherit its
          // ownership. The signature proves who wrote it, not what it is for.
          final other = await policy(kbId: 'some-other-kb')
              .signedJson(ownerKeys.secretKey);
          await expectLater(
            WorkspacePolicy.verified(
              other,
              ownerPublicKey: ownerKeys.publicKey,
              expectedKbId: _kb,
            ),
            throwsA(
              isA<WorkspacePolicyException>().having(
                (e) => e.message,
                'message',
                contains('signed for Knowledge Base'),
              ),
            ),
          );
        },
      );
    });

    group('malformed input', () {
      Future<void> refuses(String json, {String? because}) => expectLater(
        WorkspacePolicy.verified(
          json,
          ownerPublicKey: ownerKeys.publicKey,
          expectedKbId: _kb,
        ),
        throwsA(
          isA<WorkspacePolicyException>().having(
            (e) => e.message,
            'message',
            because == null ? isNotEmpty : contains(because),
          ),
        ),
      );

      test('refuses non-JSON, non-objects, and missing halves', () async {
        await refuses('not json at all', because: 'not valid JSON');
        await refuses('[]', because: 'not an object');
        await refuses(
          '{"policy":{}}',
          because: 'missing its body or signature',
        );
        await refuses('{"signature":"AAAA"}', because: 'missing its body');
      });

      test('refuses a garbled signature without throwing raw', () async {
        final signed = jsonDecode(
          await policy().signedJson(ownerKeys.secretKey),
        ) as Map<String, Object?>;
        signed['signature'] = 'not base64 !!!';
        await refuses(jsonEncode(signed), because: 'malformed');
      });

      test(
        'refuses a future policy version rather than half-believing it',
        () async {
          final signed = jsonDecode(
            await policy().signedJson(ownerKeys.secretKey),
          ) as Map<String, Object?>;
          (signed['policy'] as Map<String, Object?>)['version'] = 99;
          await refuses(jsonEncode(signed), because: 'Update DaySeven');
        },
      );

      test(
        'a signature that could not be checked is not a silent failure',
        () async {
          // Wrong-sized key: the crypto cannot answer. That must read as
          // "could not be checked", never as "checked and passed".
          final signed = await policy().signedJson(ownerKeys.secretKey);
          await expectLater(
            WorkspacePolicy.verified(
              signed,
              ownerPublicKey: const [1, 2, 3],
              expectedKbId: _kb,
            ),
            throwsA(
              isA<WorkspacePolicyException>().having(
                (e) => e.message,
                'message',
                contains('could not be checked'),
              ),
            ),
          );
        },
      );
    });
  });
}
