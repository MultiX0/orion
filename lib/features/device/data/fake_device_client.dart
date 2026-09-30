import 'dart:async';
import 'dart:math';

import '../../../core/result.dart';
import 'fake_script.dart';
import '../../conversation/domain/tool_call.dart';
import '../../conversation/domain/tool_call_status.dart';
import '../../conversation/domain/turn.dart';
import '../domain/connection_status.dart';
import '../domain/device_client.dart';
import '../domain/device_config.dart';
import '../domain/device_info.dart';
import '../domain/device_mode.dart';
import '../domain/device_state.dart';
import '../domain/turn_source.dart';
import '../domain/ws_event.dart';

/// An in-memory board. It runs a scripted turn every few seconds so screens
/// have something alive to show without a board or the mock.
class FakeDeviceClient implements DeviceClient {
  FakeDeviceClient({this.autoTurns = true, Random? random})
    : _random = random ?? Random() {
    _seedHistory();
  }

  static const autoTurnEvery = Duration(seconds: 9);

  final bool autoTurns;
  final Random _random;
  final _events = StreamController<WsEvent>.broadcast();
  final _connection = StreamController<ConnectionStatus>.broadcast();
  final _history = <Turn>[];
  final _bootedAt = DateTime.now();

  var _status = ConnectionStatus.disconnected;
  var _state = FakeScript.state;
  var _config = FakeScript.config;
  Timer? _rssiTimer;
  Timer? _autoTimer;
  var _turnCounter = 42;
  var _turnRunning = false;
  var _stopRequested = false;

  @override
  Stream<WsEvent> get events => _events.stream;

  @override
  Stream<ConnectionStatus> get connection => _connection.stream;

  @override
  ConnectionStatus get connectionStatus => _status;

  @override
  Future<void> reconnect() async {
    _setStatus(ConnectionStatus.disconnected);
    await connect();
  }

  @override
  Future<void> connect() async {
    if (_status == ConnectionStatus.connected) return;
    _setStatus(ConnectionStatus.connecting);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (_events.isClosed) return;
    _setStatus(ConnectionStatus.connected);
    _emit(
      WsEvent.state(
        ts: _now,
        mode: _state.mode,
        wifiRssi: _state.wifiRssi,
        volume: _state.volume,
        muted: _state.muted,
        wakeWordEnabled: _state.wakeWordEnabled,
      ),
    );
    _rssiTimer = Timer.periodic(const Duration(seconds: 5), (_) => _tickRssi());
    if (autoTurns) {
      _autoTimer = Timer.periodic(autoTurnEvery, (_) {
        if (_turnRunning) return;
        unawaited(_runTurn(_nextId(), TurnSource.wake, null, hadImage: false));
      });
    }
  }

  @override
  Future<void> disconnect() async {
    _rssiTimer?.cancel();
    _autoTimer?.cancel();
    _setStatus(ConnectionStatus.disconnected);
  }

  void dispose() {
    _rssiTimer?.cancel();
    _autoTimer?.cancel();
    _stopRequested = true;
    unawaited(_events.close());
    unawaited(_connection.close());
  }

  @override
  Future<Result<DeviceInfo>> info() async =>
      Ok(FakeScript.info(bootedAt: _bootedAt, name: _config.deviceName));

  @override
  Future<Result<DeviceState>> state() async => Ok(_state);

  @override
  Future<Result<DeviceConfig>> config() async => Ok(_config);

  @override
  Future<Result<DeviceConfig>> updateConfig(DeviceConfig patch) async {
    _config = FakeScript.merge(_config, patch);
    if (patch.volume != null || patch.wakeWordEnabled != null) {
      _state = _state.copyWith(
        volume: _config.volume ?? _state.volume,
        wakeWordEnabled: _config.wakeWordEnabled ?? _state.wakeWordEnabled,
      );
      _emit(
        WsEvent.state(
          ts: _now,
          volume: _state.volume,
          wakeWordEnabled: _state.wakeWordEnabled,
        ),
      );
    }
    return Ok(_config);
  }

  @override
  Future<Result<String>> talk({String? text}) =>
      _startTurn(text == null ? TurnSource.button : TurnSource.app, text);

  @override
  Future<Result<String>> askWithSnapshot(String text) =>
      _startTurn(TurnSource.appSnapshot, text, hadImage: true);

  @override
  Future<Result<void>> say(String text) async {
    if (_turnRunning) {
      return const Err(DeviceFailure('busy', 'Orion is in a turn right now'));
    }
    unawaited(_speak());
    return const Ok(null);
  }

  @override
  Future<Result<void>> stop() async {
    _stopRequested = true;
    return const Ok(null);
  }

  @override
  Future<Result<void>> restart() async {
    unawaited(_reboot());
    return const Ok(null);
  }

  @override
  Future<Result<List<Turn>>> history({int limit = 20, String? before}) async {
    return Ok(FakeScript.page(_history, limit, before));
  }

  Future<Result<String>> _startTurn(
    TurnSource source,
    String? text, {
    bool hadImage = false,
  }) async {
    if (_status != ConnectionStatus.connected) {
      return const Err(NetworkFailure('Orion is offline'));
    }
    if (_turnRunning) {
      return const Err(DeviceFailure('busy', 'Orion is in a turn right now'));
    }
    final id = _nextId();
    unawaited(_runTurn(id, source, text, hadImage: hadImage));
    return Ok(id);
  }

  Future<void> _runTurn(
    String id,
    TurnSource source,
    String? text, {
    required bool hadImage,
  }) async {
    _turnRunning = true;
    _stopRequested = false;
    final startedAt = _now;
    final line = FakeScript.lines[_turnCounter % FakeScript.lines.length];
    final transcript = text ?? line.$1;
    final reply = text == null ? line.$2 : _replyFor(text);
    _emit(WsEvent.turnStart(ts: _now, turnId: id, source: source));
    _setMode(DeviceMode.listening, level: 0.4);
    if (await _wait(600)) return _abort(id);
    _emit(WsEvent.turnTranscript(ts: _now, turnId: id, text: transcript));
    _setMode(DeviceMode.thinking);
    if (await _wait(1500)) return _abort(id);
    final tools = <ToolCall>[];
    if (_turnCounter % 3 == 0) {
      final call = ToolCall(
        id: 'c$_turnCounter',
        name: 'open_app',
        args: const {'name': 'spotify'},
      );
      _emit(WsEvent.turnTool(ts: _now, turnId: id, toolCall: call));
      if (await _wait(400)) return _abort(id);
      final done = call.copyWith(status: ToolCallStatus.done, result: 'ok');
      tools.add(done);
      _emit(WsEvent.turnTool(ts: _now, turnId: id, toolCall: done));
    }
    _emit(WsEvent.turnReply(ts: _now, turnId: id, text: reply));
    _emit(WsEvent.ttsStart(ts: _now, turnId: id));
    _setMode(DeviceMode.speaking);
    if (await _wait(3000)) return _abort(id);
    _emit(WsEvent.ttsEnd(ts: _now, turnId: id));
    const timings = FakeScript.liveTimings;
    _emit(WsEvent.turnEnd(ts: _now, turnId: id, timingsMs: timings));
    _history.add(
      Turn(
        id: id,
        startedAt: startedAt,
        transcript: transcript,
        reply: reply,
        hadImage: hadImage,
        toolCalls: tools,
        timingsMs: timings,
      ),
    );
    _state = _state.copyWith(lastTurnId: id);
    _finish();
  }

  Future<void> _speak() async {
    _turnRunning = true;
    _emit(const WsEvent.ttsStart(turnId: 'say'));
    _setMode(DeviceMode.speaking);
    await _wait(2000);
    _emit(const WsEvent.ttsEnd(turnId: 'say'));
    _finish();
  }

  Future<void> _reboot() async {
    await disconnect();
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!_events.isClosed) await connect();
  }

  void _abort(String id) {
    _emit(WsEvent.turnEnd(ts: _now, turnId: id));
    _finish();
  }

  void _finish() {
    _turnRunning = false;
    _stopRequested = false;
    _setMode(DeviceMode.idle);
  }

  /// Sleeps in small steps so stop() can cut in. Returns true when stopped.
  Future<bool> _wait(int ms) async {
    var left = ms;
    while (left > 0) {
      if (_stopRequested || _events.isClosed) return true;
      final step = min(100, left);
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
    return _stopRequested;
  }

  void _tickRssi() {
    _state = _state.copyWith(wifiRssi: -48 - _random.nextInt(10));
    _emit(WsEvent.state(ts: _now, wifiRssi: _state.wifiRssi));
  }

  void _setMode(DeviceMode mode, {double? level}) {
    _state = _state.copyWith(mode: mode, level: level);
    _emit(WsEvent.state(ts: _now, mode: mode, level: level));
  }

  void _setStatus(ConnectionStatus status) {
    _status = status;
    if (!_connection.isClosed) _connection.add(status);
  }

  void _emit(WsEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _nextId() {
    _turnCounter++;
    return 't_${_turnCounter.toString().padLeft(5, '0')}';
  }

  String _replyFor(String text) =>
      'You said "$text". The fake board can only listen, not think.';

  void _seedHistory() => _history.addAll(FakeScript.seededHistory(_now));

  DateTime get _now => DateTime.now();
}
