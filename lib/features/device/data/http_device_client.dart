import 'dart:async';
import 'dart:convert';

import '../../../core/network/api_paths.dart';
import '../../../core/network/device_api.dart';
import '../../../core/network/reconnecting_socket.dart';
import '../../../core/result.dart';
import '../../conversation/domain/turn.dart';
import '../domain/connection_status.dart';
import '../domain/device_client.dart';
import '../domain/device_config.dart';
import '../domain/device_info.dart';
import '../domain/device_state.dart';
import '../domain/ws_event.dart';

/// The real board over REST and one WebSocket.
class HttpDeviceClient implements DeviceClient {
  HttpDeviceClient({required DeviceApi api, ReconnectingSocket? socket})
    : _api = api,
      // Every 5 s: the board drops a link after 15 s of silence, which is how
      // its lights go out for a phone that walked away without closing.
      _socket =
          socket ??
          ReconnectingSocket(
            uriOf: () => api.wsUri,
            pingEvery: const Duration(seconds: 5),
          );

  final DeviceApi _api;
  final ReconnectingSocket _socket;
  final _events = StreamController<WsEvent>.broadcast();
  StreamSubscription<String>? _sub;

  @override
  Stream<WsEvent> get events => _events.stream;

  @override
  Stream<ConnectionStatus> get connection => _socket.status;

  @override
  ConnectionStatus get connectionStatus => _socket.current;

  @override
  Future<void> connect() async {
    _sub ??= _socket.messages.listen(_onMessage);
    await _socket.start();
  }

  @override
  Future<void> reconnect() async {
    _sub ??= _socket.messages.listen(_onMessage);
    await _socket.reconnectNow();
  }

  @override
  Future<void> disconnect() async {
    await _sub?.cancel();
    _sub = null;
    await _socket.stop();
  }

  /// The DeviceApi is owned by its provider, so it is not closed here.
  Future<void> dispose() async {
    await disconnect();
    await _socket.dispose();
    await _events.close();
  }

  @override
  Future<Result<DeviceInfo>> info() async =>
      _parsed(await _api.getJson(ApiPaths.info), DeviceInfo.fromJson);

  @override
  Future<Result<DeviceState>> state() async =>
      _parsed(await _api.getJson(ApiPaths.state), DeviceState.fromJson);

  @override
  Future<Result<DeviceConfig>> config() async =>
      _parsed(await _api.getJson(ApiPaths.config), DeviceConfig.fromJson);

  @override
  Future<Result<DeviceConfig>> updateConfig(DeviceConfig patch) async =>
      _parsed(
        await _api.postJson(ApiPaths.config, body: patch.toJson()),
        DeviceConfig.fromJson,
      );

  @override
  Future<Result<String>> talk({String? text}) async => _turnId(
    await _api.postJson(
      ApiPaths.talk,
      body: text == null ? null : <String, dynamic>{'text': text},
    ),
  );

  @override
  Future<Result<String>> askWithSnapshot(String text) async => _turnId(
    await _api.postJson(
      ApiPaths.talkSnapshot,
      body: <String, dynamic>{'text': text},
    ),
  );

  @override
  Future<Result<void>> say(String text) async => (await _api.postJson(
    ApiPaths.say,
    body: <String, dynamic>{'text': text},
  )).map((_) {});

  @override
  Future<Result<void>> stop() async =>
      (await _api.postJson(ApiPaths.stop)).map((_) {});

  @override
  Future<Result<void>> restart() async =>
      (await _api.postJson(ApiPaths.restart)).map((_) {});

  @override
  Future<Result<List<Turn>>> history({int limit = 20, String? before}) async {
    final result = await _api.getJson(
      ApiPaths.history,
      query: <String, dynamic>{'limit': limit, 'before': ?before},
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) => _parseTurns(value),
    };
  }

  Result<List<Turn>> _parseTurns(Map<String, dynamic> json) {
    try {
      final raw = json['turns'];
      if (raw is! List) return const Err(ParseFailure('No turns in history'));
      return Ok(<Turn>[
        for (final entry in raw) Turn.fromJson(entry as Map<String, dynamic>),
      ]);
    } on Object catch (e) {
      return Err(ParseFailure('History did not parse: $e'));
    }
  }

  Result<T> _parsed<T>(
    Result<Map<String, dynamic>> result,
    T Function(Map<String, dynamic>) parse,
  ) => switch (result) {
    Err(:final failure) => Err(failure),
    Ok(:final value) => _tryParse(value, parse),
  };

  Result<T> _tryParse<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    try {
      return Ok(parse(json));
    } on Object catch (e) {
      return Err(ParseFailure('The board sent something unexpected: $e'));
    }
  }

  Result<String> _turnId(Result<Map<String, dynamic>> result) =>
      switch (result) {
        Err(:final failure) => Err(failure),
        Ok(:final value) =>
          value['turn_id'] is String
              ? Ok(value['turn_id'] as String)
              : const Err(ParseFailure('No turn_id in the answer')),
      };

  /// One bad event must not kill the socket, so unknown shapes are dropped.
  void _onMessage(String raw) {
    if (_events.isClosed) return;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return;
      _events.add(WsEvent.fromJson(json));
    } on Object {
      return;
    }
  }
}
