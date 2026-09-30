import 'dart:typed_data';

import '../../../core/result.dart';
import '../domain/llm_provider.dart';
import '../domain/model_info.dart';
import '../domain/provider_kind.dart';
import '../domain/provider_repository.dart';

/// Canned model lists and a canned reply, with realistic delays.
class FakeProviderRepository implements ProviderRepository {
  static const _models = <ProviderKind, List<ModelInfo>>{
    ProviderKind.openai: [
      ModelInfo(
        id: 'gpt-4o',
        contextLength: 128000,
        supportsVision: true,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'gpt-4o-mini',
        contextLength: 128000,
        supportsVision: true,
        supportsTools: true,
      ),
      ModelInfo(id: 'o3-mini', contextLength: 200000, supportsTools: true),
      // The real list does not say what these are; the speech pickers go by
      // id. Marked not chat here so the fake brain picker stays clean.
      ModelInfo(id: 'whisper-1', supportsChat: false),
      ModelInfo(id: 'gpt-4o-mini-transcribe', supportsChat: false),
      ModelInfo(id: 'gpt-4o-mini-tts', supportsChat: false),
      ModelInfo(id: 'tts-1', supportsChat: false),
    ],
    ProviderKind.anthropic: [
      ModelInfo(
        id: 'claude-sonnet-5',
        contextLength: 200000,
        supportsVision: true,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'claude-opus-5',
        contextLength: 200000,
        supportsVision: true,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'claude-haiku-4-5-20251001',
        contextLength: 200000,
        supportsVision: true,
        supportsTools: true,
      ),
    ],
    ProviderKind.deepinfra: [
      ModelInfo(
        id: 'google/gemma-4-31B-it-turbo',
        contextLength: 262144,
        supportsVision: true,
        supportsChat: true,
      ),
      // DeepInfra lists embeddings and speech next to the chat models.
      ModelInfo(id: 'BAAI/bge-m3', contextLength: 8192, supportsChat: false),
      ModelInfo(
        id: 'Qwen/Qwen3-ASR-1.7B',
        supportsChat: false,
        supportsSpeechToText: true,
        supportsTextToSpeech: false,
      ),
      ModelInfo(
        id: 'openai/whisper-large-v3-turbo',
        supportsChat: false,
        supportsSpeechToText: true,
        supportsTextToSpeech: false,
      ),
      ModelInfo(
        id: 'Qwen/Qwen3-TTS',
        supportsChat: false,
        supportsSpeechToText: false,
        supportsTextToSpeech: true,
      ),
      ModelInfo(
        id: 'hexgrad/Kokoro-82M',
        supportsChat: false,
        supportsSpeechToText: false,
        supportsTextToSpeech: true,
      ),
      ModelInfo(
        id: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
        contextLength: 131072,
        supportsVision: false,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'Qwen/Qwen2.5-VL-72B-Instruct',
        contextLength: 32768,
        supportsVision: true,
        supportsTools: true,
      ),
      ModelInfo(
        id: 'deepseek-ai/DeepSeek-V3',
        contextLength: 163840,
        supportsVision: false,
        supportsTools: true,
      ),
    ],
    ProviderKind.groq: [
      ModelInfo(id: 'llama-3.3-70b-versatile', contextLength: 131072),
      ModelInfo(id: 'whisper-large-v3', supportsChat: false),
      ModelInfo(id: 'whisper-large-v3-turbo', supportsChat: false),
    ],
    ProviderKind.ollama: [
      ModelInfo(id: 'llama3.2', displayName: 'llama3.2 (3B)'),
      ModelInfo(id: 'llava', displayName: 'llava (7B)', supportsVision: true),
      ModelInfo(id: 'qwen2.5', displayName: 'qwen2.5 (7B)'),
    ],
    ProviderKind.custom: [ModelInfo(id: 'local-model')],
  };

  @override
  Future<Result<List<ModelInfo>>> listModels(LlmProvider provider) async {
    await _delay(600);
    return Ok(_models[provider.kind] ?? const []);
  }

  @override
  Future<Result<String>> testCompletion(
    LlmProvider provider,
    String model,
  ) async {
    await _delay(900);
    return const Ok('Hi, glad you are here.');
  }

  @override
  Future<Result<String>> describeImage(
    LlmProvider provider,
    String model,
    Uint8List png,
    String prompt,
  ) async {
    await _delay(1200);
    return const Ok(
      'An editor on the left, a browser on the right, and a chat window '
      'nobody has read in an hour.',
    );
  }

  @override
  Future<Result<void>> validateKey(LlmProvider provider) async {
    await _delay(500);
    return const Ok(null);
  }

  @override
  Future<Result<void>> pushToDevice(LlmProvider provider, String model) async {
    await _delay(300);
    return const Ok(null);
  }

  @override
  Future<Result<void>> mirrorToHarness(
    LlmProvider provider,
    String model,
  ) async => const Ok(null);

  Future<void> _delay(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
}
