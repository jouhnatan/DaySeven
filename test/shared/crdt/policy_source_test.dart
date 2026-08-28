/// Choosing between the authority, the cache, and refusing to start.
///
/// The case that matters most is the last one: not knowing the rules must
/// never read as there being none, because that is the difference between
/// routing a protected edit into a proposal and writing it straight out.
library;

import 'package:dayseven/shared/crdt/policy_source.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:flutter_test/flutter_test.dart';

const _kb = '01a01830-9749-7398-9626-dab25d46040e';
const _otherKb = '01a01830-9749-7398-9626-dab25d46041f';
const _owner = 'user-owner';
const _editor = 'user-editor';
const _protectedFile = 'file-protected';

WorkspacePolicy policy({String kbId = _kb}) => WorkspacePolicy(
  kbId: kbId,
  ownerId: _owner,
  issuedAt: DateTime.utc(2026, 8, 26),
  members: const {_owner: PolicyRole.owner, _editor: PolicyRole.editor},
  protectedFiles: const {
    _protectedFile: ProtectedFile(
      fileId: _protectedFile,
      minimumPublishRole: PolicyRole.owner,
    ),
  },
);

void main() {
  group('policy source', () {
    test('the authority wins, and what it said is what gets cached', () {
      final source = resolvePolicySource(
        authoritative: policy(),
        cachedDocument: null,
        expectedKbId: _kb,
      );

      expect(source, isA<PolicyFromAuthority>());
      final authority = source as PolicyFromAuthority;
      expect(authority.policy.hasSameRulesAs(policy()), isTrue);
      expect(
        WorkspacePolicy.fromCache(
          authority.documentToCache,
          expectedKbId: _kb,
        ).hasSameRulesAs(policy()),
        isTrue,
      );
    });

    test('a stale cache is ignored while the authority is reachable', () {
      // The cached copy protects nothing; the authority protects a file. The
      // authority is the one to believe.
      final stale = WorkspacePolicy(
        kbId: _kb,
        ownerId: _owner,
        issuedAt: DateTime.utc(2026, 1, 1),
        members: const {_owner: PolicyRole.owner, _editor: PolicyRole.editor},
        protectedFiles: const {},
      );

      final source = resolvePolicySource(
        authoritative: policy(),
        cachedDocument: stale.cacheJson(),
        expectedKbId: _kb,
      );

      expect(source, isA<PolicyFromAuthority>());
      expect(
        (source as PolicyFromAuthority).policy.canWriteDirectly(
          userId: _editor,
          fileId: _protectedFile,
        ),
        isFalse,
      );
    });

    test('an unreachable authority falls back to the cache', () {
      final source = resolvePolicySource(
        authoritative: null,
        cachedDocument: policy().cacheJson(),
        expectedKbId: _kb,
        authorityError: 'the network is down',
      );

      expect(source, isA<PolicyFromCache>());
      expect(
        (source as PolicyFromCache).policy.canWriteDirectly(
          userId: _editor,
          fileId: _protectedFile,
        ),
        isFalse,
      );
    });

    test('no authority and no cache refuses to start', () {
      final source = resolvePolicySource(
        authoritative: null,
        cachedDocument: null,
        expectedKbId: _kb,
        authorityError: 'the network is down',
      );

      expect(source, isA<PolicyUnavailable>());
      final unavailable = source as PolicyUnavailable;
      expect(unavailable.message, contains('could not be read'));
      // The person needs to know their own work is not at risk.
      expect(unavailable.message, contains('Local editing is unaffected'));
      expect(unavailable.message, contains('the network is down'));
    });

    test('a corrupted cache refuses rather than being half-believed', () {
      final source = resolvePolicySource(
        authoritative: null,
        cachedDocument: '{ this is not the file we wrote',
        expectedKbId: _kb,
      );

      expect(source, isA<PolicyUnavailable>());
    });

    test("a cache from another Knowledge Base is not a usable fallback", () {
      // Otherwise copying a folder would carry its ownership and protection
      // into a workspace it says nothing about.
      final source = resolvePolicySource(
        authoritative: null,
        cachedDocument: policy(kbId: _otherKb).cacheJson(),
        expectedKbId: _kb,
      );

      expect(source, isA<PolicyUnavailable>());
    });
  });
}
