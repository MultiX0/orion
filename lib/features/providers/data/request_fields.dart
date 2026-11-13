import '../domain/llm_provider.dart';
import '../domain/provider_kind.dart';

/// What a provider's chat endpoint refuses, so a request leaves it out.
///
/// Anthropic's newer models refuse `temperature`. OpenAI's newer models
/// refuse it too, and want `max_completion_tokens` in place of
/// `max_tokens`. Anything else (a custom server, OpenRouter routing to one of
/// those) is learned from its first 400 and remembered by base URL and model
/// for as long as the app runs. The board does the same (cloud_reply.c).
class RequestFields {
  RequestFields._();

  static final _noTemperature = <String>{};
  static final _completionTokens = <String>{};

  /// Claude models that take "between_tools" (Sonnet 5.5) or that cannot
  /// stop thinking at all (Opus 5.5), learned from their 400.
  static final _betweenTools = <String>{};
  static final _thinks = <String>{};

  static String _key(LlmProvider p, String model) => '${p.baseUrl}|$model';

  static bool _omitsTemperature(LlmProvider p, String model) =>
      p.kind == ProviderKind.anthropic ||
      p.kind == ProviderKind.openai ||
      _noTemperature.contains(_key(p, model));

  static bool _usesCompletionTokens(LlmProvider p, String model) =>
      p.kind == ProviderKind.openai ||
      _completionTokens.contains(_key(p, model));

  /// The token limit and, where taken and asked for, the temperature. A
  /// model that thinks first spends its reasoning out of
  /// max_completion_tokens, so that limit is never below 200.
  ///
  /// Claude thinks by default, out of the same limit, so a short answer
  /// could end before its first word: Anthropic gets thinking off unless
  /// [thinking] asks for it. A Claude model that refuses that (learned from
  /// its 400) thinks, with room for it.
  static Map<String, dynamic> of(
    LlmProvider provider,
    String model, {
    required int maxTokens,
    double? temperature,
    bool thinking = false,
  }) {
    final completion = _usesCompletionTokens(provider, model);
    final key = _key(provider, model);
    final anthropic = provider.kind == ProviderKind.anthropic;
    final off = anthropic && !thinking && !_thinks.contains(key);
    final room = anthropic && (thinking || _thinks.contains(key));
    final limit = room && maxTokens < 2000 ? 2000 : maxTokens;
    return <String, dynamic>{
      if (completion)
        'max_completion_tokens': limit < 200 ? 200 : limit
      else
        'max_tokens': limit,
      if (temperature != null && !_omitsTemperature(provider, model))
        'temperature': temperature,
      if (off)
        'thinking': <String, String>{
          'type': _betweenTools.contains(key) ? 'between_tools' : 'disabled',
        },
    };
  }

  /// A 400's body names a field this provider refuses: remembered, and true
  /// when sending the request again would now go differently.
  static bool learn(LlmProvider provider, String model, String errorBody) {
    final key = _key(provider, model);
    if (provider.kind == ProviderKind.anthropic &&
        errorBody.contains('thinking') &&
        !_thinks.contains(key)) {
      if (errorBody.contains('between_tools') && _betweenTools.add(key)) {
        return true;
      }
      return _thinks.add(key);
    }
    if (errorBody.contains('temperature') &&
        !_omitsTemperature(provider, model)) {
      _noTemperature.add(key);
      return true;
    }
    if (errorBody.contains('max_tokens') &&
        errorBody.contains('max_completion_tokens') &&
        !_usesCompletionTokens(provider, model)) {
      _completionTokens.add(key);
      return true;
    }
    return false;
  }

  /// Tests only.
  static void forgetLearned() {
    _noTemperature.clear();
    _completionTokens.clear();
    _thinks.clear();
    _betweenTools.clear();
  }
}
