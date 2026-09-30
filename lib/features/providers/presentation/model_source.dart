import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import '../data/llm_providers.dart';
import '../domain/llm_provider.dart';
import '../domain/model_info.dart';
import '../domain/voice_presets.dart';
import 'speech_models.dart';

/// Only a model the provider marks as not for chat is left out.
bool isChatModel(ModelInfo model) => model.supportsChat != false;

/// Where a model picker's list comes from, and which models it offers.
class ModelSource {
  const ModelSource({
    required this.models,
    required this.name,
    required this.keyId,
    this.needsKey = true,
    this.fits = isChatModel,
  });

  /// The language model's list, for a provider in the Providers config.
  ModelSource.brain(LlmProvider provider)
    : models = modelListProvider(provider.id),
      name = provider.name,
      keyId = provider.id,
      needsKey = provider.needsKey,
      fits = isChatModel;

  /// A speech stage's list: [preset]'s endpoint at [baseUrl], cut to the
  /// models that fit [stage].
  factory ModelSource.speech({
    required StagePreset preset,
    required String baseUrl,
    required String stage,
  }) {
    final url = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final host = Uri.tryParse(url)?.host ?? '';
    return ModelSource(
      models: speechModelListProvider(preset.keyId, url),
      name: !preset.isCustom
          ? preset.name
          : host.isEmpty
          ? 'the endpoint'
          : host,
      keyId: preset.keyId,
      fits: (m) => fitsSpeechStage(m, stage: stage, presetId: preset.id),
    );
  }

  final ProviderBase<AsyncValue<List<ModelInfo>>> models;

  /// Who serves the list, in the picker's label and its errors.
  final String name;

  /// Where the key sits in the SecretStore, to say whether one is on file.
  final String keyId;
  final bool needsKey;
  final bool Function(ModelInfo model) fits;
}
