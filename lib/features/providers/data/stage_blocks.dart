import '../../device/domain/device_config.dart';
import '../../device/domain/llm_config.dart';
import '../../device/domain/stage_config.dart';
import '../domain/fish_config.dart';
import '../domain/llm_provider.dart';
import '../domain/provider_presets.dart';
import '../domain/voice_presets.dart';
import '../domain/voice_stages.dart';

/// The keys to send, looked up by the caller from the SecretStore. Null
/// means none on file, and the block goes without one, which keeps the
/// board's stored key.
typedef StageKeys = ({String? llm, String? stt, String? tts});

const _llmLabels = {
  'deepinfra',
  'openai',
  'anthropic',
  'groq',
  'openrouter',
  'ollama',
};

/// The three blocks of config version 2 for what the user picked.
DeviceConfig stageBlocks({
  required LlmProvider llm,
  required VoiceStages stages,
  required FishConfig fish,
  required StageKeys keys,
}) {
  final stt = VoicePresets.sttById(stages.stt.presetId);
  final tts = VoicePresets.ttsById(stages.tts.presetId);
  return DeviceConfig(
    llm: LlmConfig(
      provider: _llmLabels.contains(llm.id) ? llm.id : 'custom',
      baseUrl: llm.baseUrl,
      apiKey: keys.llm,
      model:
          llm.selectedModel ??
          (llm.id == ProviderPresets.deepinfra.id
              ? ProviderPresets.defaultModel
              : null),
    ),
    stt: stt.isFish
        ? SttConfig(
            provider: StageProvider.fish,
            apiKey: keys.stt,
            model: stages.stt.model ?? stt.model,
          )
        : SttConfig(
            provider: StageProvider.openaiCompatible,
            baseUrl: stages.stt.baseUrl ?? stt.baseUrl,
            apiKey: keys.stt,
            model: stages.stt.model ?? stt.model,
          ),
    tts: tts.isFish
        ? TtsConfig(
            provider: StageProvider.fish,
            apiKey: keys.tts,
            model: fish.ttsModel,
            // Orion Voice: ProvidersConfigNotifier pins it on load.
            voice: fish.voiceId ?? tts.voice,
          )
        : TtsConfig(
            provider: StageProvider.openaiCompatible,
            baseUrl: stages.tts.baseUrl ?? tts.baseUrl,
            apiKey: keys.tts,
            model: stages.tts.model ?? tts.model,
            voice: stages.tts.voice ?? tts.voice,
          ),
  );
}

/// One block's JSON without its key, for comparing against what the board
/// already has.
Map<String, dynamic> withoutKey(Object? block) {
  if (block is! Map<String, dynamic>) return const {};
  return {...block}..remove('api_key');
}

/// True when [ours] names a value the board does not have. Fields we do not
/// send do not count.
bool differs(Map<String, dynamic> ours, Map<String, dynamic>? board) {
  if (board == null) return true;
  for (final MapEntry(:key, :value) in ours.entries) {
    if (board[key] != value) return true;
  }
  return false;
}
