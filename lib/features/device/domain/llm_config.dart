import 'package:freezed_annotation/freezed_annotation.dart';

part 'llm_config.freezed.dart';
part 'llm_config.g.dart';

/// The llm block of the board config. Every field is optional so a partial
/// POST /api/config only touches what it names.
@freezed
abstract class LlmConfig with _$LlmConfig {
  const factory LlmConfig({
    /// A label the app shows: deepinfra, openai, groq and so on. Config
    /// version 2 only; the board itself uses base_url, api_key and model.
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? systemPrompt,
  }) = _LlmConfig;

  factory LlmConfig.fromJson(Map<String, dynamic> json) =>
      _$LlmConfigFromJson(json);
}
