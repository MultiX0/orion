import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../data/llm_providers.dart';
import '../data/stage_setup.dart';
import '../domain/llm_provider.dart';
import '../domain/model_info.dart';
import '../domain/provider_kind.dart';

part 'speech_models.g.dart';

/// Models on a speech endpoint, with the key stored under [keyId]. Every
/// speech preset but Fish is OpenAI-compatible, so GET /models serves.
@riverpod
Future<List<ModelInfo>> speechModelList(
  Ref ref,
  String keyId,
  String baseUrl,
) async {
  if (baseUrl.isEmpty) throw const NotFoundFailure('Add the base URL first.');
  final key = await ref
      .watch(secretStoreProvider)
      .read(SecretKeys.providerApiKey(keyId));
  final endpoint = LlmProvider(
    id: keyId,
    // DeepInfra, OpenAI and Groq keys are stored under the provider's name.
    kind: ProviderKind.values.asNameMap()[keyId] ?? ProviderKind.custom,
    name: keyId,
    baseUrl: baseUrl,
    apiKey: key,
  );
  final result = await ref
      .watch(providerRepositoryProvider)
      .listModels(endpoint);
  return result.getOrThrow();
}

/// Whether [model] can serve [stage], Stage.stt or Stage.tts. A tag is
/// taken at its word. OpenAI and Groq do not tag, so their speech models
/// are known by id: whisper-1, gpt-4o-transcribe, gpt-4o-mini-transcribe,
/// tts-1, tts-1-hd, gpt-4o-mini-tts and their dated snapshots, and Groq's
/// whisper-large-v3 family. An endpoint that does not say offers everything.
bool fitsSpeechStage(
  ModelInfo model, {
  required String stage,
  required String presetId,
}) {
  final listening = stage == Stage.stt;
  final said = listening
      ? model.supportsSpeechToText
      : model.supportsTextToSpeech;
  if (said != null) return said;
  final id = model.id.toLowerCase();
  return switch (presetId) {
    // DeepInfra tags every model it lists, so no tag means not speech.
    'deepinfra' => false,
    'openai' || 'groq' =>
      listening
          ? id.contains('whisper') || id.contains('transcribe')
          : id.startsWith('tts-') || id.contains('-tts'),
    _ => true,
  };
}
