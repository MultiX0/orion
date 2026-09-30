import 'llm_provider.dart';
import 'provider_kind.dart';

/// The built-in providers. Base URLs are starting points the user can edit.
abstract final class ProviderPresets {
  static const openai = LlmProvider(
    id: 'openai',
    kind: ProviderKind.openai,
    name: 'OpenAI',
    baseUrl: 'https://api.openai.com/v1',
  );

  static const anthropic = LlmProvider(
    id: 'anthropic',
    kind: ProviderKind.anthropic,
    name: 'Anthropic',
    baseUrl: 'https://api.anthropic.com/v1',
  );

  /// The board's default brain: Gemma 4 31B on DeepInfra answers, and
  /// GLM 5.3 Flash, thinking, does the tasks on the PC and phone.
  static const deepinfra = LlmProvider(
    id: 'deepinfra',
    kind: ProviderKind.deepinfra,
    name: 'DeepInfra',
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    selectedModel: defaultModel,
    thinkingModel: defaultThinkingModel,
  );

  /// Fast, sees pictures, and good Arabic: every everyday answer.
  static const defaultModel = 'google/gemma-4-31B-it-turbo';

  /// Finishes the most tasks in tool/brain_eval.dart, and the fastest, with
  /// the best Arabic of the models tried. It sees pictures and says so when a
  /// task is not done, where Gemma claims songs played that it only searched
  /// for. See docs/HARNESS.md, "Choosing the models".
  static const defaultThinkingModel = 'zai-org/GLM-5.3-Flash';

  static const groq = LlmProvider(
    id: 'groq',
    kind: ProviderKind.groq,
    name: 'Groq',
    baseUrl: 'https://api.groq.com/openai/v1',
  );

  static const openrouter = LlmProvider(
    id: 'openrouter',
    kind: ProviderKind.openrouter,
    name: 'OpenRouter',
    baseUrl: 'https://openrouter.ai/api/v1',
  );

  static const ollama = LlmProvider(
    id: 'ollama',
    kind: ProviderKind.ollama,
    name: 'Ollama',
    baseUrl: 'http://localhost:11434/v1',
  );

  static const custom = LlmProvider(
    id: 'custom',
    kind: ProviderKind.custom,
    name: 'Custom',
    baseUrl: '',
  );

  static const all = [
    deepinfra,
    openai,
    anthropic,
    groq,
    openrouter,
    ollama,
    custom,
  ];
}
