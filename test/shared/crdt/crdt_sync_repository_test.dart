/// The wire format between the CRDT session and Postgres.
///
/// Bytes crossing this boundary are Yjs updates: opaque, order-sensitive, and
/// silently ruinous if a single one is dropped or reordered. These tests are
/// about that encoding surviving the trip, not about yrs semantics.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/crdt_sync_repository.dart';
import 'package:dayseven/shared/crdt/workspace_policy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _CapturedRequest {
  const _CapturedRequest(this.method, this.uri, this.body);

  final String method;
  final Uri uri;
  final Object? body;
}

void main() {
  group('CrdtUpdate', () {
    test('decodes a durable row', () {
      final update = CrdtUpdate.fromRow({
        'id': 42,
        'author_id': 'author-1',
        'update': base64Encode(const [0, 1, 2, 253, 254, 255]),
      });
      expect(update.id, 42);
      expect(update.authorId, 'author-1');
      expect(update.bytes, const [0, 1, 2, 253, 254, 255]);
      expect(update.isDurable, isTrue);
    });

    test('a broadcast row has no durable position', () {
      final update = CrdtUpdate.fromRow({
        'author_id': 'author-1',
        'update': base64Encode(const [7]),
      });
      expect(update.id, 0);
      expect(update.isDurable, isFalse);
    });

    test('round-trips arbitrary bytes through a broadcast payload', () {
      final bytes = Uint8List.fromList(
        List<int>.generate(512, (i) => (i * 7 + 3) % 256),
      );
      final payload = CrdtUpdate(
        id: 0,
        authorId: 'author-1',
        bytes: bytes,
      ).toBroadcastPayload();
      expect(CrdtUpdate.fromRow(payload).bytes, bytes);
    });
  });

  group('CrdtCatchUp', () {
    test('a fresh peer receives a snapshot and the updates after it', () {
      final catchUp = CrdtCatchUp.fromRpc({
        'snapshot': base64Encode(const [1, 2, 3]),
        'snapshot_through': 3,
        'updates': [
          {
            'id': 4,
            'author_id': 'a',
            'update': base64Encode(const [4]),
          },
          {
            'id': 5,
            'author_id': 'b',
            'update': base64Encode(const [5]),
          },
        ],
        'cursor': 5,
      });
      expect(catchUp.snapshot, const [1, 2, 3]);
      expect(catchUp.snapshotThrough, 3);
      expect(catchUp.updates.map((u) => u.id), [4, 5]);
      expect(catchUp.cursor, 5);
      expect(catchUp.isEmpty, isFalse);
    });

    test('a caught-up peer receives nothing but keeps its cursor', () {
      final catchUp = CrdtCatchUp.fromRpc({
        'snapshot': null,
        'snapshot_through': null,
        'updates': <Object>[],
        'cursor': 5,
      });
      expect(catchUp.isEmpty, isTrue);
      // The cursor must survive an empty pull, or the next pull refetches
      // everything and the log is replayed on every poll.
      expect(catchUp.cursor, 5);
    });

    test('a peer past the snapshot gets updates without the snapshot', () {
      final catchUp = CrdtCatchUp.fromRpc({
        'snapshot': null,
        'updates': [
          {
            'id': 6,
            'author_id': 'a',
            'update': base64Encode(const [6]),
          },
        ],
        'cursor': 6,
      });
      expect(catchUp.snapshot, isNull);
      expect(catchUp.updates.single.id, 6);
    });
  });

  group('bytea encoding', () {
    // PostgREST hands `bytea` to Postgres as a hex literal. Getting the padding
    // wrong corrupts every update containing a byte below 0x10 — which, for
    // Yjs, is most of them.
    String encode(List<int> bytes) => CrdtSyncRepositoryTestAccess.bytea(bytes);

    test('pads every byte to two hex digits', () {
      expect(encode(const [0, 1, 15, 16, 255]), r'\x00010f10ff');
    });

    test('encodes an empty payload as the empty bytea', () {
      expect(encode(const []), r'\x');
    });

    test('covers the whole byte range without loss', () {
      final all = List<int>.generate(256, (i) => i);
      final hex = encode(all).substring(2);
      expect(hex.length, 512);
      final decoded = [
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      expect(decoded, all);
    });
  });

  group('policy publishing', () {
    Future<_CapturedRequest> publishAs(PolicyRole role) async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final captured = Completer<_CapturedRequest>();
      server.listen((request) async {
        final rawBody = await utf8.decoder.bind(request).join();
        captured.complete(
          _CapturedRequest(
            request.method,
            request.uri,
            rawBody.isEmpty ? null : jsonDecode(rawBody),
          ),
        );
        request.response.headers.contentType = ContentType.json;
        request.response.write(
          request.method == 'PATCH' ? '{"id":"kb-1"}' : 'null',
        );
        await request.response.close();
      });

      final client = SupabaseClient(
        'http://${server.address.host}:${server.port}',
        'sb_publishable_test',
        accessToken: () async => 'test-access-token',
      );
      try {
        await CrdtSyncRepository(client).publishPolicy(
          kbId: 'kb-1',
          publicKey: const [0, 1, 15, 255],
          signedDocument: '{"policy":"signed"}',
          actorRole: role,
        );
        return await captured.future;
      } finally {
        await client.dispose();
        await server.close(force: true);
      }
    }

    test('an owner atomically updates the RLS-protected row', () async {
      final request = await publishAs(PolicyRole.owner);

      expect(request.method, 'PATCH');
      expect(request.uri.path, '/rest/v1/knowledge_bases');
      expect(request.uri.queryParameters['id'], 'eq.kb-1');
      expect(request.body, {
        'policy_public_key': r'\x00010fff',
        'policy_document': '{"policy":"signed"}',
      });
    });

    test('a co-owner keeps the narrow policy RPC', () async {
      final request = await publishAs(PolicyRole.coOwner);

      expect(request.method, 'POST');
      expect(request.uri.path, '/rest/v1/rpc/publish_policy');
      expect(request.body, {
        'p_kb_id': 'kb-1',
        'p_public_key': r'\x00010fff',
        'p_document': '{"policy":"signed"}',
      });
    });
  });
}
