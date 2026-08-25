import 'package:dayseven/shared/presence/peer_presence.dart';
import 'package:dayseven/shared/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';

PeerPresence _peer(
  String userId, {
  String? path,
  String? blockId,
  bool idle = false,
  DateTime? at,
}) => PeerPresence(
  userId: userId,
  username: userId,
  displayName: userId.toUpperCase(),
  relativePath: path,
  documentId: path == null ? null : 'doc-$path',
  blockId: blockId,
  idle: idle,
  updatedAt: at ?? DateTime.utc(2026, 8, 25, 12),
);

void main() {
  group('payload', () {
    test('round-trips through JSON', () {
      final peer = _peer('alice', path: 'Places/Aldenmoor.md', blockId: 'p2');
      final decoded = PeerPresence.fromJson(peer.toJson());
      expect(decoded, peer);
    });

    test('a null position round-trips as absent rather than empty', () {
      final decoded = PeerPresence.fromJson(_peer('alice').toJson())!;
      expect(decoded.relativePath, isNull);
      expect(decoded.blockId, isNull);
    });

    test('carries nothing but identifiers', () {
      final json = _peer('alice', path: 'a.md', blockId: 'p1').toJson();
      expect(json.keys, everyElement(isNot(contains('content'))));
      expect(json.keys.toSet(), {
        'user_id',
        'username',
        'display_name',
        'path',
        'document_id',
        'block_id',
        'updated_at',
      });
    });

    test('a payload from another build is discarded, not thrown on', () {
      expect(PeerPresence.fromJson(const {}), isNull);
      expect(PeerPresence.fromJson(const {'user_id': 42}), isNull);
      final partial = PeerPresence.fromJson(const {'user_id': 'alice'});
      expect(partial, isNotNull);
      expect(partial!.displayName, isEmpty);
      expect(partial.updatedAt.millisecondsSinceEpoch, 0);
    });

    test('falls back through display name, username, then a neutral mark', () {
      expect(_peer('alice').initial, 'A');
      final noName = PeerPresence(
        userId: 'u',
        username: 'bru',
        displayName: '  ',
        updatedAt: _epoch,
      );
      expect(noName.initial, 'B');
      expect(noName.label, '@bru');
      final nothing = PeerPresence(
        userId: 'u',
        username: '',
        displayName: '',
        updatedAt: _epoch,
      );
      expect(nothing.initial, '?');
    });
  });

  group('folding presence state', () {
    test('drops yourself', () {
      final peers = peersFromPresencePayloads([
        [_peer('me', path: 'a.md').toJson()],
        [_peer('alice', path: 'a.md').toJson()],
      ], selfUserId: 'me');
      expect(peers.keys, ['alice']);
    });

    test('two windows of one person collapse to the newest', () {
      final peers = peersFromPresencePayloads([
        [
          _peer(
            'alice',
            path: 'old.md',
            at: DateTime.utc(2026, 8, 25, 11),
          ).toJson(),
          _peer(
            'alice',
            path: 'new.md',
            at: DateTime.utc(2026, 8, 25, 12),
          ).toJson(),
        ],
      ], selfUserId: 'me');
      expect(peers.length, 1);
      expect(peers['alice']!.relativePath, 'new.md');
    });

    test('an unreadable payload does not take the readable ones with it', () {
      final peers = peersFromPresencePayloads([
        [const {'nonsense': true}],
        [_peer('alice', path: 'a.md').toJson()],
      ], selfUserId: 'me');
      expect(peers.keys, ['alice']);
    });
  });

  group('grouping', () {
    test('by path, skipping peers with nothing open', () {
      final byPath = peersByPath([
        _peer('alice', path: 'a.md'),
        _peer('bru', path: 'a.md'),
        _peer('cyd'),
      ]);
      expect(byPath.keys, ['a.md']);
      expect(byPath['a.md']!.map((p) => p.userId), ['alice', 'bru']);
    });

    test('by block, within one document only', () {
      final byBlock = peersByBlock(
        [
          _peer('alice', path: 'a.md', blockId: 'p1'),
          _peer('bru', path: 'b.md', blockId: 'p1'),
        ],
        relativePath: 'a.md',
        knownBlockIds: {'p1'},
      );
      expect(byBlock['p1']!.map((p) => p.userId), ['alice']);
    });

    test(
      'a peer on a block this copy does not have gets no marker, but is '
      'still in the document',
      () {
        // The two copies legitimately differ while a proposal is pending.
        final peers = [_peer('alice', path: 'a.md', blockId: 'theirs')];
        expect(
          peersByBlock(
            peers,
            relativePath: 'a.md',
            knownBlockIds: {'mine'},
          ),
          isEmpty,
        );
        expect(peersByPath(peers)['a.md'], hasLength(1));
      },
    );

    test('order is stable across rebuilds', () {
      final peers = [_peer('zed', path: 'a.md'), _peer('alice', path: 'a.md')];
      expect(peersByPath(peers)['a.md']!.map((p) => p.userId), [
        'alice',
        'zed',
      ]);
      expect(peersByPath(peers.reversed)['a.md']!.map((p) => p.userId), [
        'alice',
        'zed',
      ]);
    });
  });

  group('colour', () {
    test('is stable for a user, so both machines agree', () {
      const id = '466839ae-d51e-4e44-a8cb-a4d966f14918';
      final first = presenceColorIndex(id, DsPresence.palette.length);
      expect(presenceColorIndex(id, DsPresence.palette.length), first);
      expect(first, inInclusiveRange(0, DsPresence.palette.length - 1));
    });

    test('stays in range for any id', () {
      for (final id in ['', 'a', 'x' * 400, '☃', '0-0-0-0']) {
        expect(
          presenceColorIndex(id, DsPresence.palette.length),
          inInclusiveRange(0, DsPresence.palette.length - 1),
        );
      }
    });
  });

  group('samePositionAs', () {
    test('ignores the timestamp, so an unchanged position is not resent', () {
      final a = _peer('alice', path: 'a.md', blockId: 'p1');
      final b = a.copyWith(updatedAt: DateTime.utc(2027));
      expect(a.samePositionAs(b), isTrue);
      expect(a == b, isFalse);
    });

    test('a moved caret is a new position', () {
      final a = _peer('alice', path: 'a.md', blockId: 'p1');
      expect(a.samePositionAs(a.copyWith(blockId: () => 'p2')), isFalse);
      expect(a.samePositionAs(a.copyWith(idle: true)), isFalse);
      expect(a.samePositionAs(a.copyWith(relativePath: () => null)), isFalse);
    });
  });
}

final _epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
