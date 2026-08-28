import 'dart:convert';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List bytes(int length, [int seed = 0]) => Uint8List.fromList(
  List.generate(length, (index) => (index * 31 + seed) % 256),
);

void main() {
  group('relay protocol v1', () {
    test('uses the fixed opcode table', () {
      expect(
        {for (final opcode in CrdtOpcode.values) opcode.name: opcode.wire},
        {
          'peerJoined': 0x01,
          'peerLeft': 0x02,
          'stateVectorRequest': 0x03,
          'crdtUpdate': 0x04,
          'proposalInventory': 0x05,
          'proposalRequest': 0x06,
          'proposalData': 0x07,
          'proposalResolution': 0x08,
          'presence': 0x09,
          'ack': 0x0a,
          'error': 0x0b,
        },
      );
    });

    test('encodes version, opcode, big-endian metadata length and body', () {
      final encoded = encodeEnvelope(
        CrdtEnvelope(
          opcode: CrdtOpcode.stateVectorRequest,
          metadata: {'messageId': 'm1'},
          body: Uint8List.fromList([7, 8, 9]),
        ),
      );
      final metadata = utf8.encode('{"messageId":"m1"}');
      expect(encoded[0], 1);
      expect(encoded[1], 3);
      expect(ByteData.sublistView(encoded).getUint32(2, Endian.big), metadata.length);
      expect(encoded.sublist(6, 6 + metadata.length), metadata);
      expect(encoded.sublist(6 + metadata.length), [7, 8, 9]);
    });

    test('round-trips binary bodies and server-attributed identity', () {
      final encoded = encodeEnvelope(
        CrdtEnvelope(
          opcode: CrdtOpcode.stateVectorRequest,
          metadata: {
            'messageId': 'm1',
            'senderId': 'peer',
            'senderRole': 'editor',
          },
          body: bytes(100),
        ),
      );
      final decoded = decodeEnvelope(encoded);
      expect(decoded.senderId, 'peer');
      expect(decoded.senderRole, 'editor');
      expect(decoded.body, bytes(100));
    });

    test('rejects text, wrong versions, unknown opcodes and bad lengths', () {
      expect(
        () => decodeEnvelope('text'),
        throwsA(
          isA<CrdtProtocolException>().having(
            (error) => error.rejection,
            'rejection',
            CrdtRejection.wrongFrameType,
          ),
        ),
      );
      final valid = encodeEnvelope(
        CrdtEnvelope(
          opcode: CrdtOpcode.stateVectorRequest,
          metadata: {'messageId': 'm1'},
        ),
      );
      expect(
        () => decodeEnvelope(Uint8List.fromList(valid)..[0] = 2),
        throwsA(isA<CrdtProtocolException>()),
      );
      expect(
        () => decodeEnvelope(Uint8List.fromList(valid)..[1] = 0xff),
        throwsA(isA<CrdtProtocolException>()),
      );
      final impossible = Uint8List.fromList(valid);
      ByteData.sublistView(impossible).setUint32(2, 1000, Endian.big);
      expect(
        () => decodeEnvelope(impossible),
        throwsA(isA<CrdtProtocolException>()),
      );
    });

    test('enforces typed control payloads', () {
      expect(
        () => encodeEnvelope(
          CrdtEnvelope(
            opcode: CrdtOpcode.proposalResolution,
            metadata: {
              'messageId': 'm',
              'proposalId': 'p',
              'status': 'pending',
            },
          ),
        ),
        throwsA(isA<CrdtProtocolException>()),
      );
      expect(
        () => encodeEnvelope(
          CrdtEnvelope(
            opcode: CrdtOpcode.proposalInventory,
            metadata: {
              'messageId': 'm',
              'proposalIds': List.generate(257, (index) => 'p$index'),
            },
          ),
        ),
        throwsA(isA<CrdtProtocolException>()),
      );
      expect(
        () => encodeEnvelope(
          CrdtEnvelope(
            opcode: CrdtOpcode.presence,
            metadata: {'messageId': 'm'},
            body: Uint8List.fromList(utf8.encode('not-json')),
          ),
        ),
        throwsA(isA<CrdtProtocolException>()),
      );
    });
  });

  group('bounded chunk assembly', () {
    late CrdtAssembler assembler;
    late DateTime now;

    setUp(() {
      now = DateTime.utc(2026, 8, 28);
      assembler = CrdtAssembler(clock: () => now);
    });

    List<Uint8List> frames(String id, Uint8List body) =>
        encodeChunkedEnvelopes(
          opcode: CrdtOpcode.crdtUpdate,
          messageId: id,
          metadata: {'senderId': 'peer'},
          body: body,
        );

    test('reassembles out-of-order chunks', () {
      final body = bytes(kMaxChunkPayloadBytes * 2 + 17);
      CrdtAssemblyResult? result;
      for (final frame in frames('large', body).reversed) {
        result = assembler.accept(frame);
      }
      expect(result!.message!.body, body);
    });

    test('accepts an identical retransmitted partial chunk', () {
      final chunks = frames('retry', bytes(kMaxChunkPayloadBytes + 1));
      expect(assembler.accept(chunks.first).isIncomplete, isTrue);
      expect(assembler.accept(chunks.first).isIncomplete, isTrue);
      expect(assembler.accept(chunks.last).isMessage, isTrue);
    });

    test('rejects completed replays', () {
      final frame = frames('once', bytes(4)).single;
      expect(assembler.accept(frame).isMessage, isTrue);
      expect(assembler.accept(frame).rejection, CrdtRejection.replay);
    });

    test('bounds pending assemblies and expires stale ones', () {
      for (var index = 0; index < 20; index++) {
        assembler.accept(
          frames('m$index', bytes(kMaxChunkPayloadBytes + 1)).first,
        );
      }
      expect(assembler.pendingCount, lessThanOrEqualTo(kMaxPendingAssemblies));
      now = now.add(kAssemblyTimeout + const Duration(seconds: 1));
      assembler.accept(frames('fresh', bytes(kMaxChunkPayloadBytes + 1)).first);
      expect(assembler.pendingCount, 1);
    });

    test('refuses bodies past the 50 MiB ceiling before allocation', () {
      expect(
        () => encodeChunkedEnvelopes(
          opcode: CrdtOpcode.crdtUpdate,
          messageId: 'huge',
          metadata: const {},
          body: Uint8List(kMaxAssembledBytes + 1),
        ),
        throwsA(isA<CrdtProtocolException>()),
      );
    });
  });
}
