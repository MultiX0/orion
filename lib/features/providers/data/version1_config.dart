import '../../device/domain/device_config.dart';
import '../../device/domain/stage_config.dart';

/// A version 2 patch in the version 1 shape: the llm block without its
/// provider label, and a fish block for whatever of the voice is on Fish.
/// A non-Fish voice stage has no version 1 form and is dropped, which is
/// why [droppedStages] exists.
Map<String, dynamic> toVersion1(DeviceConfig v2) {
  final out = <String, dynamic>{};
  final json = v2.toJson()
    ..remove('stt')
    ..remove('tts');
  for (final MapEntry(:key, :value) in json.entries) {
    if (key == 'llm' && value is Map<String, dynamic>) {
      out['llm'] = {...value}..remove('provider');
    } else {
      out[key] = value;
    }
  }
  final fish = <String, dynamic>{};
  final tts = v2.tts;
  final stt = v2.stt;
  if (tts != null && tts.provider == StageProvider.fish) {
    if (tts.apiKey != null) fish['api_key'] = tts.apiKey;
    if (tts.voice != null) fish['voice_id'] = tts.voice;
    if (tts.model != null) fish['tts_model'] = tts.model;
  }
  if (stt != null && stt.provider == StageProvider.fish) {
    fish.putIfAbsent('api_key', () => stt.apiKey);
    fish.removeWhere((_, value) => value == null);
  }
  if (fish.isNotEmpty) out['fish'] = fish;
  return out;
}

/// The voice stages a version 1 board cannot take.
List<String> droppedStages(DeviceConfig v2) => [
  if (v2.stt case SttConfig(
    :final provider?,
  ) when provider != StageProvider.fish)
    'stt',
  if (v2.tts case TtsConfig(
    :final provider?,
  ) when provider != StageProvider.fish)
    'tts',
];
