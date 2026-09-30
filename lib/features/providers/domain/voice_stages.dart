import 'package:freezed_annotation/freezed_annotation.dart';

part 'voice_stages.freezed.dart';
part 'voice_stages.g.dart';

/// The user's pick for one voice stage. No key here: keys live in the
/// SecretStore under the preset's keyId.
@freezed
abstract class StageChoice with _$StageChoice {
  const factory StageChoice({
    required String presetId,
    String? baseUrl,
    String? model,

    /// Text to speech only. Fish TTS keeps its model and voice in
    /// FishConfig, where the voice library writes them; these fields are
    /// for the other providers.
    String? voice,
  }) = _StageChoice;

  factory StageChoice.fromJson(Map<String, dynamic> json) =>
      _$StageChoiceFromJson(json);
}

/// Speech to text and text to speech, chosen separately. Defaults are the
/// board's: Fish transcribe-1 and Fish s2.1-pro-free.
@freezed
abstract class VoiceStages with _$VoiceStages {
  const VoiceStages._();

  const factory VoiceStages({
    @Default(StageChoice(presetId: 'fish', model: 'transcribe-1'))
    StageChoice stt,
    @Default(StageChoice(presetId: 'fish')) StageChoice tts,
  }) = _VoiceStages;

  factory VoiceStages.fromJson(Map<String, dynamic> json) =>
      _$VoiceStagesFromJson(json);

  bool get sttOnFish => stt.presetId == 'fish';
  bool get ttsOnFish => tts.presetId == 'fish';

  /// Both on Fish: one key field serves both, and both blocks carry it.
  bool get sharedFishKey => sttOnFish && ttsOnFish;
  bool get anyFish => sttOnFish || ttsOnFish;
}
