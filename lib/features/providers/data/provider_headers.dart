import '../domain/llm_provider.dart';
import '../domain/provider_kind.dart';

/// Auth headers per provider. Anthropic's OpenAI-compatible layer wants its
/// own key header and a version on top of the bearer token.
Map<String, String> headersFor(LlmProvider provider) {
  final key = provider.apiKey;
  return switch (provider.kind) {
    ProviderKind.ollama => const <String, String>{},
    ProviderKind.anthropic => <String, String>{
      if (key != null) ...<String, String>{
        'authorization': 'Bearer $key',
        'x-api-key': key,
      },
      'anthropic-version': '2023-06-01',
    },
    _ => <String, String>{if (key != null) 'authorization': 'Bearer $key'},
  };
}
