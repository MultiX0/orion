import 'package:freezed_annotation/freezed_annotation.dart';

import 'provider_kind.dart';

part 'llm_provider.freezed.dart';
part 'llm_provider.g.dart';

/// One OpenAI-compatible endpoint the user can point the board at.
@freezed
abstract class LlmProvider with _$LlmProvider {
  const LlmProvider._();

  const factory LlmProvider({
    required String id,
    required ProviderKind kind,
    required String name,

    /// No trailing slash.
    required String baseUrl,

    /// Lives in SecretStore. Only ever set in memory, never written to JSON.
    @JsonKey(includeToJson: false) String? apiKey,
    String? selectedModel,

    /// The model the PC and phone brain use: one that thinks before it acts,
    /// for turns that click through apps. selectedModel stays the board's
    /// own, fast one for plain questions. Null: selectedModel for both.
    String? thinkingModel,
  }) = _LlmProvider;

  factory LlmProvider.fromJson(Map<String, dynamic> json) =>
      _$LlmProviderFromJson(json);

  bool get needsKey => kind != ProviderKind.ollama;
}
