import '../../conversation/domain/turn_timings.dart';
import '../../conversation/domain/turn.dart';
import '../../providers/domain/fish_config.dart';
import '../domain/device_config.dart';
import '../domain/device_info.dart';
import '../domain/device_mode.dart';
import '../domain/device_state.dart';
import '../domain/llm_config.dart';
import '../domain/pc_config.dart';

/// What the fake board "hears" and "says". Kept out of FakeDeviceClient so
/// that file stays about the lifecycle rather than the words.
abstract final class FakeScript {
  static const lines = <(String, String)>[
    ('what is on my desk', 'A keyboard, a mug, and a very tired cat.'),
    ('what time is it', 'It is ten past nine.'),
    ('open spotify', 'Opening Spotify on your PC.'),
    ('how is the sky tonight', 'Clear. Orion is up in the south east.'),
    ('remind me to stretch', 'I will nudge you in twenty minutes.'),
  ];

  /// What the fake board looks like the moment it comes up.
  static const state = DeviceState(
    mode: DeviceMode.idle,
    wifiRssi: -52,
    volume: 70,
  );

  /// Secrets are masked here exactly as a real board masks them.
  static const config = DeviceConfig(
    deviceName: 'Orion',
    volume: 70,
    wakeWordEnabled: true,
    language: 'en',
    timeZone: 'UTC0',
    llm: LlmConfig(
      baseUrl: 'https://api.deepinfra.com/v1/openai',
      apiKey: 'sk-...4f2a',
      model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
      systemPrompt: 'You are Orion.',
    ),
    fish: FishConfig(apiKey: 'fa-...91c0', voiceId: 'orion-default'),
    pc: PcConfig(enabled: false),
  );

  static DeviceInfo info({required DateTime bootedAt, String? name}) =>
      DeviceInfo(
        deviceId: 'orion-mock',
        name: name ?? 'Orion',
        fwVersion: '0.1.0-mock',
        hw: 't-cameraplus-s3',
        ip: '127.0.0.1',
        uptimeS: DateTime.now().difference(bootedAt).inSeconds,
        hasCamera: true,
      );

  /// A partial POST /api/config, merged block by block the way the board
  /// does it: a null field means "leave this one alone".
  static DeviceConfig merge(DeviceConfig current, DeviceConfig patch) =>
      current.copyWith(
        deviceName: patch.deviceName ?? current.deviceName,
        volume: patch.volume ?? current.volume,
        wakeWordEnabled: patch.wakeWordEnabled ?? current.wakeWordEnabled,
        language: patch.language ?? current.language,
        timeZone: patch.timeZone ?? current.timeZone,
        llm: patch.llm ?? current.llm,
        fish: patch.fish ?? current.fish,
        pc: patch.pc ?? current.pc,
      );

  /// Newest first with a cursor, the way GET /api/history answers.
  static List<Turn> page(List<Turn> all, int limit, String? before) {
    var turns = all.reversed.toList();
    if (before != null) {
      final index = turns.indexWhere((t) => t.id == before);
      if (index >= 0) turns = turns.sublist(index + 1);
    }
    return turns.take(limit).toList();
  }

  /// What a live turn reports. The seeded ones are slower, being older.
  static const liveTimings = TurnTimings(
    stt: 600,
    llm: 1500,
    ttsFirstByte: 480,
    total: 5100,
  );

  static const _timings = TurnTimings(
    stt: 1400,
    llm: 2100,
    ttsFirstByte: 480,
    total: 5200,
  );

  /// Three old turns, so the Conversation screen is never empty on a fresh
  /// launch. Oldest first, matching the order the real history comes back in.
  static List<Turn> seededHistory(DateTime now) => <Turn>[
    for (var i = 0; i < 3; i++)
      Turn(
        id: 't_${(40 + i).toString().padLeft(5, '0')}',
        startedAt: now.subtract(Duration(minutes: 30 - i * 7)),
        transcript: lines[i].$1,
        reply: lines[i].$2,
        timingsMs: _timings,
      ),
  ];
}
