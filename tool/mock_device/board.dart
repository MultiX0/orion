import 'dart:async';
import 'dart:math';

import 'board_config.dart';
import 'tool_script.dart';
import 'turn_history.dart';

typedef BoardEvent = Map<String, dynamic>;

/// The fake board's brain: state, config, history and the scripted turn.
/// Everything is in memory and resets when the process restarts.
class MockBoard {
  MockBoard({
    this.deviceId = 'orion-a1b2',
    bool configVersion1 = false,
    Random? random,
  }) : _random = random ?? Random(),
       _config = BoardConfig(version1: configVersion1);

  final String deviceId;
  final Random _random;
  final _events = StreamController<BoardEvent>.broadcast();
  final _history = TurnHistory();
  final _bootedAt = DateTime.now();

  /// Set by /api/provision. While null the board answers without a token,
  /// which is what a fresh board does and what the demo needs.
  String? appToken;

  String mode = 'idle';
  int wifiRssi = -52;
  int volume = 70;
  bool wakeWordEnabled = true;
  bool muted = false;
  String? lastTurnId;
  String? error;

  /// Points at the desktop harness. Null means no PC, and then the board
  /// never calls a tool at all.
  ToolRunner? onToolCall;

  /// GET /tools on the desktop, fetched at the start of every turn.
  Future<Set<String>> Function()? availableTools;

  final BoardConfig _config;

  bool get configVersion1 => _config.version1;

  Map<String, dynamic> get config => _config.values;

  Timer? _rssiTimer;
  var _turnCounter = 42;
  var _turnRunning = false;
  var _stopRequested = false;

  Stream<BoardEvent> get events => _events.stream;
  bool get isTurnRunning => _turnRunning;

  void start() {
    _rssiTimer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      wifiRssi = -48 - _random.nextInt(12);
      emit(<String, dynamic>{'type': 'state', 'wifi_rssi': wifiRssi});
    });
  }

  Future<void> dispose() async {
    _rssiTimer?.cancel();
    _stopRequested = true;
    await _events.close();
  }

  Map<String, dynamic> info() => <String, dynamic>{
    'device_id': deviceId,
    'name': config['device_name'],
    'fw_version': '0.1.0-mock',
    'hw': 't-cameraplus-s3',
    'ip': '127.0.0.1',
    'uptime_s': DateTime.now().difference(_bootedAt).inSeconds,
    'has_camera': true,
    if (!_config.version1) ...<String, dynamic>{
      'config_version': 2,
      'providers': <String, dynamic>{
        'llm': ['openai_compatible'],
        'stt': ['fish', 'openai_compatible'],
        'tts': ['fish', 'openai_compatible'],
      },
    },
  };

  /// POST /api/config/test with what is stored.
  Map<String, dynamic> testStage(String stage) => _config.test(stage);

  Map<String, dynamic> state() => <String, dynamic>{
    'mode': mode,
    'wifi_rssi': wifiRssi,
    'battery_pct': null,
    'volume': volume,
    'wake_word_enabled': wakeWordEnabled,
    'muted': muted,
    'last_turn_id': lastTurnId,
    'error': error,
  };

  /// The state event the board sends the moment a socket connects.
  BoardEvent fullStateEvent() => <String, dynamic>{
    'type': 'state',
    'mode': mode,
    'wifi_rssi': wifiRssi,
    'volume': volume,
    'muted': muted,
    'wake_word_enabled': wakeWordEnabled,
  };

  /// Merges a partial config and mirrors the fields that also live in the
  /// state, so the app sees a volume change without asking again. Throws
  /// [ConfigRejected] and stores nothing when a value is invalid.
  Map<String, dynamic> mergeConfig(Map<String, dynamic> patch) {
    final problem = _config.merge(patch);
    if (problem != null) throw ConfigRejected(problem);
    final changed = <String, dynamic>{'type': 'state'};
    if (patch.containsKey('volume')) {
      volume = (config['volume'] as num).toInt();
      changed['volume'] = volume;
    }
    if (patch.containsKey('wake_word_enabled')) {
      wakeWordEnabled = config['wake_word_enabled'] == true;
      changed['wake_word_enabled'] = wakeWordEnabled;
    }
    if (changed.length > 1) emit(changed);
    return config;
  }

  Map<String, dynamic> history({int limit = 20, String? before}) =>
      _history.page(limit: limit, before: before);

  String nextTurnId() {
    _turnCounter++;
    return 't_${_turnCounter.toString().padLeft(5, '0')}';
  }

  void emit(BoardEvent event) {
    if (_events.isClosed) return;
    _events.add(<String, dynamic>{
      ...event,
      'ts': DateTime.now().toUtc().toIso8601String(),
    });
  }

  void stopTurn() => _stopRequested = true;

  /// The scripted turn from docs/DEVICE_PROTOCOL.md: listening, thinking,
  /// then speaking, with the events a real board would push.
  Future<void> runTurn(
    String id, {
    required String source,
    String? text,
    bool hadImage = false,
  }) async {
    _turnRunning = true;
    _stopRequested = false;
    final startedAt = DateTime.now().toUtc();
    final line = TurnHistory.script[_turnCounter % TurnHistory.script.length];
    final transcript = text ?? line.$1;
    final reply = text == null ? line.$2 : _replyFor(text);

    emit(<String, dynamic>{
      'type': 'turn.start',
      'turn_id': id,
      'source': source,
    });
    _setMode('listening');
    if (await _sleep(600)) return _abort(id);

    emit(<String, dynamic>{
      'type': 'turn.transcript',
      'turn_id': id,
      'text': transcript,
    });
    _setMode('thinking');
    if (await _sleep(1500)) return _abort(id);

    // "ask me first" and "act on your own" change the setting on the board
    // itself, so the choice holds wherever it was made.
    final mode = ToolScript.approvalFromText(transcript);
    if (mode != null) {
      mergeConfig(<String, dynamic>{
        'pc': <String, dynamic>{'approval': mode},
      });
    }

    final calls = <Map<String, dynamic>>[];
    final tool = mode == null ? await _runTool(id, transcript) : null;
    if (tool != null) calls.add(tool);
    if (_stopRequested) return _abort(id);

    final spoken = mode != null
        ? ToolScript.approvalReply(mode)
        : ToolScript.replyWith(reply, tool);
    emit(<String, dynamic>{
      'type': 'turn.reply',
      'turn_id': id,
      'text': spoken,
    });
    emit(<String, dynamic>{'type': 'tts.start', 'turn_id': id});
    _setMode('speaking');
    if (await _sleep(3000)) return _abort(id);
    emit(<String, dynamic>{'type': 'tts.end', 'turn_id': id});

    final timings = <String, dynamic>{
      'stt': 600,
      'llm': 1500,
      'tts_first_byte': 480,
      'total': 5100,
    };
    emit(<String, dynamic>{
      'type': 'turn.end',
      'turn_id': id,
      'timings_ms': timings,
    });
    _history.add(<String, dynamic>{
      'id': id,
      'started_at': startedAt.toIso8601String(),
      'transcript': transcript,
      'reply': spoken,
      'had_image': hadImage,
      'tool_calls': calls,
      'timings_ms': timings,
    });
    lastTurnId = id;
    _finish();
  }

  /// POST /api/say: speak without thinking.
  Future<void> runSay(String text) async {
    _turnRunning = true;
    _stopRequested = false;
    emit(<String, dynamic>{'type': 'tts.start', 'turn_id': 'say'});
    _setMode('speaking');
    await _sleep(1500 + text.length * 40);
    emit(<String, dynamic>{'type': 'tts.end', 'turn_id': 'say'});
    _finish();
  }

  /// Fetches the desktop's tool list, lets the script pick one, then runs it
  /// for real and reports every status change as a `turn.tool` event.
  Future<Map<String, dynamic>?> _runTool(String turnId, String text) async {
    final run = onToolCall;
    if (run == null || _config.pc['enabled'] != true) return null;
    final available = await availableTools?.call() ?? const <String>{};
    final chosen = ToolScript.forText(
      text,
      pcEnabled: true,
      turnCounter: _turnCounter,
      available: available,
    );
    if (chosen == null) return null;

    final callId = 'c$_turnCounter';
    var call = <String, dynamic>{
      'id': callId,
      'name': chosen.name,
      'args': chosen.args,
      'status': 'pending',
    };
    _emitTool(turnId, call);
    final outcome = await run(
      callId,
      turnId,
      chosen.name,
      chosen.args,
      _config.approval,
      (update) => _emitTool(turnId, call = _merge(call, update)),
    );
    call = _merge(call, outcome);
    _emitTool(turnId, call);
    return call;
  }

  void _emitTool(String turnId, Map<String, dynamic> call) => emit(
    <String, dynamic>{'type': 'turn.tool', 'turn_id': turnId, 'call': call},
  );

  Map<String, dynamic> _merge(
    Map<String, dynamic> call,
    Map<String, dynamic> outcome,
  ) => <String, dynamic>{
    ...call,
    'status': outcome['status'] ?? call['status'],
    if (outcome['result'] != null) 'result': outcome['result'],
    if (outcome['message'] != null) 'message': outcome['message'],
    if (outcome['job_id'] != null) 'job_id': outcome['job_id'],
  };

  void _abort(String id) {
    emit(<String, dynamic>{'type': 'turn.end', 'turn_id': id});
    _finish();
  }

  void _finish() {
    _turnRunning = false;
    _stopRequested = false;
    _setMode('idle');
  }

  void _setMode(String next) {
    mode = next;
    emit(<String, dynamic>{'type': 'state', 'mode': mode});
  }

  /// Sleeps in small steps so /api/stop can cut in. True means stopped.
  Future<bool> _sleep(int ms) async {
    var left = ms;
    while (left > 0) {
      if (_stopRequested || _events.isClosed) return true;
      final step = min(100, left);
      await Future<void>.delayed(Duration(milliseconds: step));
      left -= step;
    }
    return _stopRequested;
  }

  String _replyFor(String text) =>
      'You asked about "$text". The mock board reads from a script, '
      'but the wiring is real.';
}

class ConfigRejected implements Exception {
  const ConfigRejected(this.message);
  final String message;
}
