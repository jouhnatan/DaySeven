import 'dart:async';
import 'dart:typed_data';

import 'package:dayseven/shared/crdt/crdt_protocol.dart';
import 'package:dayseven/shared/crdt/crdt_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSocket implements CrdtSocket {
  final controller = StreamController<Object?>();
  final sent = <Uint8List>[];
  bool closed = false;

  @override
  Future<void> get ready => Future.value();
  @override
  Stream<Object?> get stream => controller.stream;
  @override
  void add(Uint8List bytes) => sent.add(Uint8List.fromList(bytes));
  @override
  Future<void> close() async {
    closed = true;
    if (!controller.isClosed) await controller.close();
  }
}

void main() {
  const room = '01a01830-9749-7398-9626-dab25d46040e';

  test('connects to the room URI with a bearer header', () async {
    final socket = FakeSocket();
    Uri? uri;
    Map<String, dynamic>? headers;
    final service = CrdtSyncService(
      roomId: room,
      accessTokenProvider: () => 'access-token',
      socketFactory: (nextUri, nextHeaders) {
        uri = nextUri;
        headers = nextHeaders;
        return socket;
      },
    );
    addTearDown(service.dispose);

    await service.connect();

    expect(
      uri.toString(),
      'wss://dayseven-server.onrender.com/ws?room=$room',
    );
    expect(headers, {'Authorization': 'Bearer access-token'});
    expect(service.state, CrdtConnectionState.connected);
  });

  test('sends binary frames and strips caller-supplied sender identity', () async {
    final socket = FakeSocket();
    final service = CrdtSyncService(
      roomId: room,
      accessTokenProvider: () => 'token',
      socketFactory: (_, _) => socket,
    );
    addTearDown(service.dispose);
    await service.connect();

    await service.send(
      opcode: CrdtOpcode.crdtUpdate,
      metadata: const {'senderId': 'forged', 'senderRole': 'owner'},
      body: const [1, 2, 3],
      messageId: 'message-1',
    );

    expect(socket.sent, hasLength(1));
    final decoded = decodeEnvelope(socket.sent.single);
    expect(decoded.senderId, isNull);
    expect(decoded.senderRole, isNull);
    expect(decoded.body, [1, 2, 3]);
  });

  test('reassembles inbound binary chunks into a typed event', () async {
    final socket = FakeSocket();
    final service = CrdtSyncService(
      roomId: room,
      accessTokenProvider: () => 'token',
      socketFactory: (_, _) => socket,
    );
    addTearDown(service.dispose);
    await service.connect();

    final event = service.events.first;
    final body = Uint8List(kMaxChunkPayloadBytes + 3);
    for (final frame in encodeChunkedEnvelopes(
      opcode: CrdtOpcode.crdtUpdate,
      messageId: 'inbound',
      metadata: const {'senderId': 'peer', 'senderRole': 'editor'},
      body: body,
    )) {
      socket.controller.add(frame);
    }

    final received = await event;
    expect(received.opcode, CrdtOpcode.crdtUpdate);
    expect(received.senderId, 'peer');
    expect(received.body, body);
  });

  test('refuses text frames without closing local documents', () async {
    final socket = FakeSocket();
    final service = CrdtSyncService(
      roomId: room,
      accessTokenProvider: () => 'token',
      socketFactory: (_, _) => socket,
    );
    addTearDown(service.dispose);
    await service.connect();

    final error = service.errors.first;
    socket.controller.add('not binary');

    expect((await error).rejection, CrdtRejection.wrongFrameType);
    expect(service.state, CrdtConnectionState.connected);
  });

  test('uses jittered capped exponential reconnect delays', () {
    expect(
      [for (var i = 0; i < 8; i++) crdtReconnectDelay(i)],
      const [1, 2, 4, 8, 16, 30, 30, 30]
          .map((seconds) => Duration(seconds: seconds)),
    );
    expect(crdtReconnectDelay(0, jitterUnit: 0), const Duration(milliseconds: 800));
    expect(crdtReconnectDelay(0, jitterUnit: 1), const Duration(milliseconds: 1200));
  });

  test('disconnect closes the socket and is intentional', () async {
    final socket = FakeSocket();
    final service = CrdtSyncService(
      roomId: room,
      accessTokenProvider: () => 'token',
      socketFactory: (_, _) => socket,
    );
    addTearDown(service.dispose);
    await service.connect();

    await service.disconnect();

    expect(socket.closed, isTrue);
    expect(service.state, CrdtConnectionState.disconnected);
  });
}
