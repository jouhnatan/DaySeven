/// The protection policy, and what happens when its cache is not what the
/// authority wrote.
///
/// Postgres is the authority; the file on disk is only a cache for a member
/// who cannot reach it. So these tests ask two things: do the permissions read
/// the way they are written, and does a damaged cache get refused rather than
/// half-believed?
library;

import 'dart:convert';

import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _otherKb = '01a01830-9749-7398-9626-dab25d46041f';
const _owner = 'user-owner';
const _editor = 'user-editor';
const _reviewer = 'user-reviewer';
const _protectedFile = 'file-protected';
const _openFile = 'file-open';

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
  group('workspace policy', () {
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

    group('offline cache', () {
      test('a cached policy reads back with the same rules', () {
        final restored = WorkspacePolicy.fromCache(
          policy().cacheJson(),
          expectedKbId: _kb,
        );

        expect(restored.hasSameRulesAs(policy()), isTrue);
        expect(restored.ownerId, _owner);
        expect(
          restored.canWriteDirectly(userId: _editor, fileId: _protectedFile),
          isFalse,
        );
      });

      test('the encoding is stable, so two machines agree byte for byte', () {
        expect(policy().cacheJson(), policy().cacheJson());
        expect(
          WorkspacePolicy.fromCache(
            policy().cacheJson(),
            expectedKbId: _kb,
          ).cacheJson(),
          policy().cacheJson(),
        );
      });

      test('a cache belonging to another Knowledge Base is refused', () {
        // Copying one workspace's cache into another would otherwise carry
        // that workspace's ownership and protection across with it.
        expect(
          () => WorkspacePolicy.fromCache(
            policy(kbId: _otherKb).cacheJson(),
            expectedKbId: _kb,
          ),
          throwsA(
            isA<WorkspacePolicyException>().having(
              (e) => e.message,
              'message',
              contains('not $_kb'),
            ),
          ),
        );
      });
    });

    group('malformed input', () {
      void refuses(String json, {String? because}) => expect(
        () => WorkspacePolicy.fromCache(json, expectedKbId: _kb),
        throwsA(
          isA<WorkspacePolicyException>().having(
            (e) => e.message,
            'message',
            because == null ? isNotEmpty : contains(because),
          ),
        ),
      );

      test('refuses non-JSON and non-objects', () {
        refuses('not json at all', because: 'not valid JSON');
        refuses('[]', because: 'not an object');
      });

      test('refuses a body with nothing in it', () {
        refuses('{}');
      });

      test('refuses a future policy version rather than half-believing it', () {
        final body = jsonDecode(policy().cacheJson()) as Map<String, Object?>;
        body['version'] = 99;
        refuses(jsonEncode(body), because: 'Update DaySeven');
      });
    });
  });
}
