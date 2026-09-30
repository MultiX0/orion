import 'package:freezed_annotation/freezed_annotation.dart';

part 'stage_config.freezed.dart';
part 'stage_config.g.dart';

/// Board provider kinds for the two voice stages.
abstract final class StageProvider {
  static const fish = 'fish';
  static const openaiCompatible = 'openai_compatible';
}

/// The stt block of config version 2. Every field is optional so a POST
/// only touches what it names. api_key omitted keeps the stored key.
@freezed
abstract class SttConfig with _$SttConfig {
  const factory SttConfig({
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) = _SttConfig;

  factory SttConfig.fromJson(Map<String, dynamic> json) =>
      _$SttConfigFromJson(json);
}

/// The tts block of config version 2. voice is a Fish voice id for fish,
/// a voice name for openai_compatible.
@freezed
abstract class TtsConfig with _$TtsConfig {
  const factory TtsConfig({
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? voice,
  }) = _TtsConfig;

  factory TtsConfig.fromJson(Map<String, dynamic> json) =>
      _$TtsConfigFromJson(json);
}
