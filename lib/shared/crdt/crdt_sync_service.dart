/// Persistent authenticated WebSocket transport for one CRDT room.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:dayseven/shared/crdt/crdt_protocol.dart';

const String kCrdtRelayOrigin = 'wss://dayseven-server.onrender.com';
const Duration kCrdtSocketConnectTimeout = Duration(seconds: 15);
const Duration kCrdtStableConnectionWindow = Duration(seconds: 10);

enum CrdtConnectionState { connected, connecting, disconnected, error }

class CrdtTransportError {
  const CrdtTransportError(this.message, {this.rejection, this.cause});

  final String message;
  final CrdtRejection? rejection;
  final Object? cause;
}

abstract interface class CrdtSocket {
  Future<void> get ready;
  Stream<Object?> get stream;
  void add(Uint8List bytes);
  Future<void> close();
}

typedef CrdtSocketFactory = FutureOr<CrdtSocket> Function(
  Uri uri,
  Map<String, dynamic> headers,
);
typedef CrdtAccessTokenProvider = FutureOr<String?> Function();

/// Interface accepted by [CrdtSession], so its document behavior can be tested
/// without opening a network socket.
abstract interface class CrdtTransport {
  String get roomId;
  Uri get connectionUri;
  CrdtConnectionState get state;
  Stream<CrdtConnectionState> get states;
  Stream<CrdtEnvelope> get events;
  Stream<CrdtTransportError> get errors;

  Future<void> connect();
  Future<void> disconnect();
  Future<String> reconcile(Uint8List stateVector);
  Future<String> send({
    required CrdtOpcode opcode,
    Map<String, Object?> metadata,
    List<int> body,
    String? messageId,
  });
}

class CrdtSyncService implements CrdtTransport {
  CrdtSyncService({
    required this.roomId,
    required this.accessTokenProvider,
    CrdtSocketFactory? socketFactory,
    Uri? relayOrigin,
    math.Random? random,
  }) : _socketFactory = socketFactory ?? _openDesktopSocket,
       _relayOrigin = relayOrigin ?? Uri.parse(kCrdtRelayOrigin),
       _random = random ?? math.Random.secure();

  @override
  final String roomId;
  final CrdtAccessTokenProvider accessTokenProvider;
  final CrdtSocketFactory _socketFactory;
  final Uri _relayOrigin;
  final math.Random _random;

  @override
  Uri get connectionUri =>
      _relayOrigin.replace(path: '/ws', queryParameters: {'room': roomId});

  final _states = StreamController<CrdtConnectionState>.broadcast();
  final _events = StreamController<CrdtEnvelope>.broadcast();
  final _errors = StreamController<CrdtTransportError>.broadcast();
  final CrdtAssembler _assembler = CrdtAssembler();

  @override
  Stream<CrdtConnectionState> get states => _states.stream;
  @override
  Stream<CrdtEnvelope> get events => _events.stream;
  @override
  Stream<CrdtTransportError> get errors => _errors.stream;

  @override
  CrdtConnectionState get state => _state;
  CrdtConnectionState _state = CrdtConnectionState.disconnected;
  Object? get lastError => _lastError;
  Object? _lastError;

  CrdtSocket? _socket;
  StreamSubscription<Object?>? _subscription;
  Timer? _reconnectTimer;
  Timer? _stableTimer;
  bool _wantConnected = false;
  bool _disposed = false;
  int _generation = 0;
  int _reconnectAttempt = 0;
  int _idCounter = 0;

  @override
  Future<void> connect() async {
    if (_disposed) throw StateError('CrdtSyncService is disposed.');
    _wantConnected = true;
    _reconnectTimer?.cancel();
    if (_state == CrdtConnectionState.connected ||
        _state == CrdtConnectionState.connecting) {
      return;
    }
    await _open();
  }

  Future<void> _open() async {
    if (!_wantConnected || _disposed) return;
    final generation = ++_generation;
    _emit(CrdtConnectionState.connecting);
    try {
      final token = await accessTokenProvider();
      if (token == null || token.trim().isEmpty) {
        throw StateError('A signed-in Supabase session is required.');
      }
      final socket = await _socketFactory(connectionUri, {
        'Authorization': 'Bearer $token',
      });
      if (generation != _generation || !_wantConnected || _disposed) {
        await socket.close();
        return;
      }
      _socket = socket;
      _subscription = socket.stream.listen(
        _receive,
        onError: (Object error, StackTrace stackTrace) {
          _drop(generation, error);
        },
        onDone: () => _drop(generation, null),
        cancelOnError: true,
      );
      await socket.ready;
      if (generation != _generation || !_wantConnected || _disposed) {
        await socket.close();
        return;
      }
      _lastError = null;
      _emit(CrdtConnectionState.connected);
      _stableTimer?.cancel();
      _stableTimer = Timer(kCrdtStableConnectionWindow, () {
        if (_state == CrdtConnectionState.connected) _reconnectAttempt = 0;
      });
    } on Object catch (error) {
      _drop(generation, error);
    }
  }

  void _receive(Object? raw) {
    final result = _assembler.accept(raw);
    if (result.isIncomplete) return;
    if (result.isRejected) {
      _errors.add(
        CrdtTransportError(
          'The relay sent an invalid CRDT frame.',
          rejection: result.rejection,
        ),
      );
      return;
    }
    _events.add(result.message!);
  }

  void _drop(int generation, Object? error) {
    if (generation != _generation || _disposed) return;
    // Invalidate this generation before cancellation can cause another done
    // callback, so one socket loss schedules one reconnect.
    _generation++;
    _stableTimer?.cancel();
    _stableTimer = null;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final socket = _socket;
    _socket = null;
    if (socket != null) unawaited(socket.close());

    if (!_wantConnected) {
      _emit(CrdtConnectionState.disconnected);
      return;
    }
    if (error != null) {
      _lastError = error;
      _emit(CrdtConnectionState.error);
      _errors.add(
        CrdtTransportError('WebSocket connection failed.', cause: error),
      );
    } else {
      _emit(CrdtConnectionState.disconnected);
    }
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (!_wantConnected || _disposed || _reconnectTimer != null) return;
    final delay = crdtReconnectDelay(
      _reconnectAttempt++,
      jitterUnit: _random.nextDouble(),
    );
    _reconnectTimer = Timer(delay, () {
      _reconnectTimer = null;
      unawaited(_open());
    });
  }

  @override
  Future<void> disconnect() async {
    _wantConnected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _stableTimer?.cancel();
    _stableTimer = null;
    _generation++;
    final subscription = _subscription;
    _subscription = null;
    if (subscription != null) await subscription.cancel();
    final socket = _socket;
    _socket = null;
    if (socket != null) await socket.close();
    _emit(CrdtConnectionState.disconnected);
  }

  @override
  Future<String> reconcile(Uint8List stateVector) =>
      send(opcode: CrdtOpcode.stateVectorRequest, body: stateVector);

  @override
  Future<String> send({
    required CrdtOpcode opcode,
    Map<String, Object?> metadata = const {},
    List<int> body = const [],
    String? messageId,
  }) async {
    final socket = _socket;
    if (_state != CrdtConnectionState.connected || socket == null) {
      throw StateError('CRDT relay is not connected.');
    }
    final id = messageId ?? _newMessageId();
    // Sender identity is server-owned. Removing it here prevents an accidental
    // local value from ever being treated as authoritative in a test relay.
    final safeMetadata = Map<String, Object?>.from(metadata)
      ..remove('senderId')
      ..remove('senderRole');
    final frames =
        opcode == CrdtOpcode.crdtUpdate || opcode == CrdtOpcode.proposalData
        ? encodeChunkedEnvelopes(
            opcode: opcode,
            messageId: id,
            metadata: safeMetadata,
            body: body,
          )
        : [
            encodeEnvelope(
              CrdtEnvelope(
                opcode: opcode,
                metadata: {...safeMetadata, 'messageId': id},
                body: Uint8List.fromList(body),
              ),
            ),
          ];
    for (final frame in frames) {
      socket.add(frame);
    }
    return id;
  }

  String _newMessageId() =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}-'
      '${(_idCounter++).toRadixString(36)}-'
      '${_random.nextInt(1 << 32).toRadixString(36)}';

  void _emit(CrdtConnectionState next) {
    if (_disposed || _state == next) return;
    _state = next;
    _states.add(next);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await disconnect();
    _disposed = true;
    await _states.close();
    await _events.close();
    await _errors.close();
  }
}

/// Jittered 1/2/4/8/16/30 second exponential backoff.
Duration crdtReconnectDelay(int attempt, {double jitterUnit = 0.5}) {
  const seconds = [1, 2, 4, 8, 16, 30];
  final base = seconds[attempt.clamp(0, seconds.length - 1)];
  final unit = jitterUnit.clamp(0.0, 1.0);
  final multiplier = 0.8 + (unit * 0.4);
  return Duration(milliseconds: (base * 1000 * multiplier).round());
}

Future<CrdtSocket> _openDesktopSocket(
  Uri uri,
  Map<String, dynamic> headers,
) async => _IoCrdtSocket(
  IOWebSocketChannel.connect(
    uri,
    headers: headers,
    pingInterval: const Duration(seconds: 20),
    connectTimeout: kCrdtSocketConnectTimeout,
  ),
);

class _IoCrdtSocket implements CrdtSocket {
  _IoCrdtSocket(this.channel);
  final WebSocketChannel channel;

  @override
  Future<void> get ready => channel.ready;
  @override
  Stream<Object?> get stream => channel.stream;
  @override
  void add(Uint8List bytes) => channel.sink.add(bytes);
  @override
  Future<void> close() => channel.sink.close();
}
