import '../../device/domain/stage_config.dart';

/// One choice for a voice stage. The board only knows two kinds, fish and
/// openai_compatible; the rest is a starting base URL and model the user
/// can edit.
class StagePreset {
  const StagePreset({
    required this.id,
    required this.name,
    required this.provider,
    required this.keyId,
    this.baseUrl,
    this.model,
    this.models = const [],
    this.voice,
  });

  final String id;
  final String name;

  /// fish or openai_compatible, what the board is told.
  final String provider;

  /// Which key in the keychain this preset uses. DeepInfra, OpenAI and
  /// Groq share the key the language model already uses; one account, one
  /// key.
  final String keyId;
  final String? baseUrl;
  final String? model;

  /// Offered as chips. A free text model field covers anything else.
  final List<String> models;
  final String? voice;

  bool get isFish => provider == StageProvider.fish;
  bool get isCustom => id == VoicePresets.customId;
}

abstract final class VoicePresets {
  static const fishKeyId = 'fish';
  static const customId = 'custom';

  /// Fish speech to text bills API credit: $0.36 per hour of audio.
  static const fishSttDollarsPerHour = 0.36;

  static const fishStt = StagePreset(
    id: 'fish',
    name: 'Fish Audio',
    provider: StageProvider.fish,
    keyId: fishKeyId,
    model: 'transcribe-1',
    models: ['transcribe-1', 'transcribe-1-pro'],
  );

  static const stt = [
    fishStt,
    StagePreset(
      id: 'deepinfra',
      name: 'DeepInfra',
      provider: StageProvider.openaiCompatible,
      keyId: 'deepinfra',
      baseUrl: 'https://api.deepinfra.com/v1/openai',
      model: 'Qwen/Qwen3-ASR-1.7B',
    ),
    StagePreset(
      id: 'groq',
      name: 'Groq',
      provider: StageProvider.openaiCompatible,
      keyId: 'groq',
      baseUrl: 'https://api.groq.com/openai/v1',
      model: 'whisper-large-v3-turbo',
    ),
    StagePreset(
      id: 'openai',
      name: 'OpenAI',
      provider: StageProvider.openaiCompatible,
      keyId: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini-transcribe',
    ),
    StagePreset(
      id: customId,
      name: 'Custom',
      provider: StageProvider.openaiCompatible,
      keyId: 'custom_stt',
    ),
  ];

  /// Orion Voice, the project's own: designed with Fish Voice Design, soft,
  /// warm and gentle, natural Arabic with a light Saudi accent and natural
  /// English, saying its name the English way. Published on Fish as unlisted,
  /// so any Fish key can use it by this id.
  static const orionVoiceId = '9a68c1d739134940a4297c996c5ca6a1';
  static const orionVoiceName = 'Orion Voice';

  static const fishTts = StagePreset(
    id: 'fish',
    name: 'Fish Audio',
    provider: StageProvider.fish,
    keyId: fishKeyId,
    model: 's2.1-pro-free',
    models: ['s2.1-pro-free', 's2.1-pro', 's2-pro', 's1'],
    voice: orionVoiceId,
  );

  static const tts = [
    fishTts,
    // On DeepInfra's /audio/speech with pcm, Qwen3-TTS is the only model
    // that speaks both the English and the Arabic test lines correctly.
    // Kokoro reads Arabic as gibberish. Voices: Serena or Vivian.
    StagePreset(
      id: 'deepinfra',
      name: 'DeepInfra',
      provider: StageProvider.openaiCompatible,
      keyId: 'deepinfra',
      baseUrl: 'https://api.deepinfra.com/v1/openai',
      model: 'Qwen/Qwen3-TTS',
      voice: 'Serena',
    ),
    StagePreset(
      id: 'openai',
      name: 'OpenAI',
      provider: StageProvider.openaiCompatible,
      keyId: 'openai',
      baseUrl: 'https://api.openai.com/v1',
      model: 'gpt-4o-mini-tts',
      voice: 'alloy',
    ),
    StagePreset(
      id: customId,
      name: 'Custom',
      provider: StageProvider.openaiCompatible,
      keyId: 'custom_tts',
    ),
  ];

  static StagePreset sttById(String? id) =>
      stt.where((p) => p.id == id).firstOrNull ?? fishStt;

  static StagePreset ttsById(String? id) =>
      tts.where((p) => p.id == id).firstOrNull ?? fishTts;

  /// Which preset a board block most likely came from, by base URL.
  static String presetIdFor(
    List<StagePreset> presets,
    String? provider,
    String? baseUrl,
  ) {
    if (provider == StageProvider.fish) return 'fish';
    final url = baseUrl?.trim() ?? '';
    return presets
            .where((p) => !p.isFish && p.baseUrl != null && p.baseUrl == url)
            .firstOrNull
            ?.id ??
        customId;
  }
}
