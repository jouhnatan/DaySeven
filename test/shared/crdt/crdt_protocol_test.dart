/// What the `crdt:<kbId>` topic accepts, and — mostly — what it refuses.
///
/// Every frame here is treated as written by someone else. These tests are the
/// specification of "untrusted input" for this protocol: the allowlist, the
/// size ceilings, chunk reassembly, and the ways a peer can try to make this
/// process allocate or misbehave.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int length, [int seed = 0]) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 31 + seed) % 256));

Map<String, dynamic> frame({
  String type = 'crdt-update',
  String mid = 'm-1',
  String sender = 'peer-1',
  int index = 0,
  int total = 1,
  List<int>? payload,
  String? rawB,
}) => {
  't': type,
  'mid': mid,
  'sender': sender,
  'i': index,
  'n': total,
  'b': rawB ?? base64Encode(payload ?? const [1, 2, 3]),
};

void main() {
  late CrdtAssembler assembler;
  late DateTime now;

  setUp(() {
    now = DateTime.utc(2026, 8, 26, 12);
    assembler = CrdtAssembler(clock: () => now);
  });

  group('the allowlist', () {
    test('accepts exactly the seven known types and nothing else', () {
      for (final type in CrdtMessageType.values) {
        final result = CrdtAssembler(
          clock: () => now,
        ).accept(frame(type: type.wire));
        expect(result.isMessage, isTrue, reason: type.wire);
        expect(result.message!.type, type);
      }
      expect(CrdtMessageType.values, hasLength(7));
    });

    test('drops an unknown type without decoding it', () {
      for (final unknown in ['eval', 'exec', 'CRDT-UPDATE', '', 'shell']) {
        final result = assembler.accept(frame(type: unknown));
        expect(result.isRejected, isTrue, reason: unknown);
        expect(result.rejection, CrdtRejection.unknownType);
      }
    });

    test('wire names are stable and independent of the Dart enum names', () {
      expect(
        CrdtMessageType.values.map((t) => t.wire),
        containsAll(<String>[
          'sync-step-1',
          'sync-step-2',
          'crdt-update',
          'awareness',
          'ping',
          'pong',
          'proposal-update',
        ]),
      );
    });
  });

  group('malformed frames', () {
    test('a missing field is refused, not defaulted', () {
      for (final key in ['mid', 'sender', 'i', 'n', 'b']) {
        final f = frame()..remove(key);
        expect(assembler.accept(f).rejection, CrdtRejection.malformed,
            reason: key);
      }
    });

    test('an empty sender or message id is refused', () {
      expect(assembler.accept(frame(sender: '')).rejection,
          CrdtRejection.malformed);
      expect(
          assembler.accept(frame(mid: '')).rejection, CrdtRejection.malformed);
    });

    test('payload that is not base64 is refused rather than thrown', () {
      expect(
        assembler.accept(frame(rawB: 'not base64 !!!')).rejection,
        CrdtRejection.malformed,
      );
    });

    test('incoherent chunk arithmetic is refused', () {
      expect(assembler.accept(frame(index: 1, total: 1)).rejection,
          CrdtRejection.incoherentChunking);
      expect(assembler.accept(frame(index: -1, total: 2)).rejection,
          CrdtRejection.incoherentChunking);
      expect(assembler.accept(frame(total: 0)).rejection,
          CrdtRejection.incoherentChunking);
    });
  });

  group('size ceilings', () {
    test('a frame over the Realtime ceiling is refused before decoding', () {
      // Refused on the *encoded* length, so the decoded bytes are never
      // allocated. That ordering is the point.
      final huge = 'A' * (kMaxRealtimePayloadBytes + 4);
      expect(assembler.accept(frame(rawB: huge)).rejection,
          CrdtRejection.tooLarge);
    });

    test('a chunk over the chunk limit is refused', () {
      expect(
        assembler.accept(frame(payload: bytes(kMaxChunkPayloadBytes + 1))).rejection,
        CrdtRejection.tooLarge,
      );
    });

    test('a control message is held to a much smaller limit', () {
      final oversizedControl = bytes(kMaxControlPayloadBytes + 1);
      expect(
        assembler.accept(frame(type: 'awareness', payload: oversizedControl)).rejection,
        CrdtRejection.tooLarge,
      );
      // The same bytes as a document update are fine.
      expect(
        CrdtAssembler(clock: () => now)
            .accept(frame(type: 'crdt-update', payload: oversizedControl))
            .isMessage,
        isTrue,
      );
    });

    test('a claimed chunk count that could exceed the cap is refused up front',
        () {
      // The peer has sent one small chunk but claims there are a million. The
      // refusal must come from the claim, not from waiting to receive them.
      final absurd = (kMaxAssembledBytes ~/ kMaxChunkPayloadBytes) + 2;
      expect(
        assembler.accept(frame(index: 0, total: absurd, payload: bytes(8))).rejection,
        CrdtRejection.tooLarge,
      );
    });
  });

  group('chunking', () {
    test('a large message round-trips through frames', () {
      final payload = bytes(kMaxChunkPayloadBytes * 2 + 17, 5);
      final frames = encodeMessage(
        type: CrdtMessageType.syncStep2,
        messageId: 'm-big',
        senderId: 'peer-1',
        payload: payload,
      );
      expect(frames, hasLength(3));

      CrdtDecodeResult? last;
      for (final f in frames) {
        last = assembler.accept(Map<String, dynamic>.from(f.payload));
      }
      expect(last!.isMessage, isTrue);
      expect(last.message!.payload, payload);
      expect(last.message!.type, CrdtMessageType.syncStep2);
    });

    test('frames arriving out of order still reassemble in order', () {
      final payload = bytes(kMaxChunkPayloadBytes * 2 + 9, 7);
      final frames = encodeMessage(
        type: CrdtMessageType.syncStep2,
        messageId: 'm-ooo',
        senderId: 'peer-1',
        payload: payload,
      ).reversed.toList();

      CrdtDecodeResult? last;
      for (final f in frames) {
        last = assembler.accept(Map<String, dynamic>.from(f.payload));
      }
      expect(last!.message!.payload, payload);
    });

    test('an incomplete set is neither a message nor a rejection', () {
      final frames = encodeMessage(
        type: CrdtMessageType.syncStep2,
        messageId: 'm-part',
        senderId: 'peer-1',
        payload: bytes(kMaxChunkPayloadBytes + 1),
      );
      final result = assembler.accept(
        Map<String, dynamic>.from(frames.first.payload),
      );
      expect(result.isIncomplete, isTrue);
      expect(result.isMessage, isFalse);
      expect(result.isRejected, isFalse);
    });

    test('a sender changing the shape mid-assembly is cut off', () {
      assembler.accept(frame(mid: 'm-x', index: 0, total: 3));
      expect(
        assembler.accept(frame(mid: 'm-x', index: 1, total: 4)).rejection,
        CrdtRejection.incoherentChunking,
      );
      expect(assembler.pendingCount, 0);
    });

    test('two peers using the same message id do not collide', () {
      final a = encodeMessage(
        type: CrdtMessageType.syncStep2,
        messageId: 'same',
        senderId: 'peer-a',
        payload: bytes(kMaxChunkPayloadBytes + 1, 1),
      );
      final b = encodeMessage(
        type: CrdtMessageType.syncStep2,
        messageId: 'same',
        senderId: 'peer-b',
        payload: bytes(kMaxChunkPayloadBytes + 1, 2),
      );
      assembler.accept(Map<String, dynamic>.from(a[0].payload));
      assembler.accept(Map<String, dynamic>.from(b[0].payload));
      final finishedA =
          assembler.accept(Map<String, dynamic>.from(a[1].payload));
      final finishedB =
          assembler.accept(Map<String, dynamic>.from(b[1].payload));
      expect(finishedA.message!.senderId, 'peer-a');
      expect(finishedB.message!.senderId, 'peer-b');
      expect(finishedA.message!.payload, isNot(finishedB.message!.payload));
    });

    test('abandoned assemblies are bounded, not accumulated forever', () {
      for (var i = 0; i < kMaxPendingAssemblies * 4; i++) {
        assembler.accept(frame(mid: 'm-$i', index: 0, total: 3));
      }
      expect(assembler.pendingCount, lessThanOrEqualTo(kMaxPendingAssemblies));
    });

    test('an assembly that stalls past the timeout is dropped', () {
      assembler.accept(frame(mid: 'm-slow', index: 0, total: 2));
      expect(assembler.pendingCount, 1);
      now = now.add(kAssemblyTimeout + const Duration(seconds: 1));
      // Any subsequent frame triggers expiry of the stale one.
      assembler.accept(frame(mid: 'm-other', index: 0, total: 2));
      expect(assembler.pendingCount, 1);
    });
  });

  group('replay rejection', () {
    test('the same completed message twice is refused the second time', () {
      expect(assembler.accept(frame(mid: 'm-1')).isMessage, isTrue);
      expect(assembler.accept(frame(mid: 'm-1')).rejection, CrdtRejection.replay);
    });

    test('a repeated chunk within one assembly is refused', () {
      assembler.accept(frame(mid: 'm-r', index: 0, total: 2));
      expect(
        assembler.accept(frame(mid: 'm-r', index: 0, total: 2)).rejection,
        CrdtRejection.replay,
      );
    });

    test('a different sender replaying an id is judged separately', () {
      assembler.accept(frame(mid: 'm-1', sender: 'peer-a'));
      expect(
        assembler.accept(frame(mid: 'm-1', sender: 'peer-b')).isMessage,
        isTrue,
      );
    });

    test('the replay window is bounded and eventually forgets', () {
      final small = CrdtAssembler(clock: () => now, replayWindow: 4);
      for (var i = 0; i < 10; i++) {
        expect(small.accept(frame(mid: 'm-$i')).isMessage, isTrue);
      }
      // m-0 has fallen out of the window, so it is accepted again. That is the
      // documented cost of a bounded window: it stops replays that arrive
      // close together, which is the only kind that can do anything.
      expect(small.accept(frame(mid: 'm-0')).isMessage, isTrue);
      expect(small.accept(frame(mid: 'm-9')).rejection, CrdtRejection.replay);
    });
  });

  test('payloads carry no interpretable structure', () {
    // The envelope has exactly six keys. Anything a sender adds is ignored
    // rather than read, so a future field cannot become an injection point in
    // an old build.
    final f = frame()
      ..['path'] = '../../etc/passwd'
      ..['cmd'] = 'rm -rf /'
      ..['url'] = 'https://example.invalid';
    final result = assembler.accept(f);
    expect(result.isMessage, isTrue);
    expect(result.message!.payload, const [1, 2, 3]);
  });
}
