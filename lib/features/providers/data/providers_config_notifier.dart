import 'dart:typed_data';

import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../domain/fish_config.dart';
import '../domain/llm_provider.dart';
import '../domain/provider_presets.dart';
import '../domain/providers_config.dart';
import '../domain/voice_presets.dart';
import '../domain/voice_stages.dart';
import 'board_config_providers.dart';
import 'llm_providers.dart';
import 'stage_blocks.dart';

part 'providers_config_notifier.g.dart';

/// Provider and Fish settings, backed by AppSettings for the shape and by
/// the SecretStore for keys. Keys never reach AppSettings.
@Riverpod(keepAlive: true, name: 'providersConfigProvider')
class ProvidersConfigNotifier extends _$ProvidersConfigNotifier {
  @override
  ProvidersConfig build() {
    final settings = ref.watch(appSettingsProvider).value;
    final saved = settings?.providers ?? const <LlmProvider>[];
    // A list saved before a preset existed still gets the new preset.
    final providers = [
      for (final p in saved) _withDefaultModel(p),
      for (final preset in ProviderPresets.all)
        if (!saved.any((p) => p.id == preset.id)) preset,
    ];
    return ProvidersConfig(
      providers: providers,
      selectedId: settings?.selectedProviderId ?? ProviderPresets.deepinfra.id,
      // Orion Voice is the only Fish voice. A different one saved by an
      // older build is dropped here, so the board and the preview never
      // hear it.
      fish: (settings?.fish ?? const FishConfig()).copyWith(
        voiceId: VoicePresets.orionVoiceId,
      ),
    );
  }

  Future<void> select(String providerId) =>
      _settings.edit((s) => s.copyWith(selectedProviderId: providerId));

  Future<void> upsert(LlmProvider provider) => _settings.edit((s) {
    final list = [...state.providers];
    final index = list.indexWhere((p) => p.id == provider.id);
    if (index < 0) {
      list.add(provider);
    } else {
      list[index] = provider;
    }
    return s.copyWith(providers: list);
  });

  Future<void> setApiKey(String providerId, String key) =>
      _secrets.write(SecretKeys.providerApiKey(providerId), key);

  Future<String?> apiKey(String providerId) =>
      _secrets.read(SecretKeys.providerApiKey(providerId));

  Future<Result<String>> testModel(String providerId, String model) async {
    final provider = await _withKey(providerId);
    if (provider == null) return const Err(NotFoundFailure('Unknown provider'));
    return ref.read(providerRepositoryProvider).testCompletion(provider, model);
  }

  /// Pushes to the board and, on desktop, mirrors into the dsh config.
  Future<Result<void>> useOnDevice(String providerId, String model) async {
    final provider = await _withKey(providerId);
    if (provider == null) return const Err(NotFoundFailure('Unknown provider'));
    await upsert(provider.copyWith(apiKey: null, selectedModel: model));
    await select(providerId);
    // Through the board config path, so a version 1 board still gets the
    // llm block it knows.
    final pushed = await ref
        .read(boardConfigRepositoryProvider)
        .send(
          stageBlocks(
            llm: provider.copyWith(selectedModel: model),
            stages: const VoiceStages(),
            fish: const FishConfig(),
            keys: (llm: provider.apiKey, stt: null, tts: null),
          ).copyWith(stt: null, tts: null),
        );
    if (pushed case Err(:final failure)) return Err(failure);
    return ref
        .read(providerRepositoryProvider)
        .mirrorToHarness(provider, model);
  }

  Future<void> setFish(FishConfig fish) async {
    final key = fish.apiKey;
    if (key != null && key.isNotEmpty) {
      await _secrets.write(SecretKeys.fishApiKey, key);
    }
    await _settings.edit((s) => s.copyWith(fish: fish.copyWith(apiKey: null)));
  }

  Future<String?> fishApiKey() => _secrets.read(SecretKeys.fishApiKey);

  Future<Result<Uint8List>> previewVoice() async {
    final fish = state.fish.copyWith(apiKey: await fishApiKey());
    return ref.read(fishRepositoryProvider).previewVoice(fish);
  }

  /// Checks a key without storing it. Screens store it on success.
  Future<Result<void>> checkProviderKey(String providerId, String key) async {
    final provider = state.providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return const Err(NotFoundFailure('Unknown provider'));
    return ref
        .read(providerRepositoryProvider)
        .validateKey(provider.copyWith(apiKey: key));
  }

  Future<Result<void>> checkFishKey(String key) =>
      ref.read(fishRepositoryProvider).validateKey(key);

  Future<LlmProvider?> _withKey(String providerId) async {
    final provider = state.providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (provider == null) return null;
    return provider.copyWith(apiKey: await apiKey(providerId));
  }

  /// DeepInfra with no model, saved by an older build or cleared by hand,
  /// is back on the board's defaults: Gemma to answer, GLM for tasks.
  static LlmProvider _withDefaultModel(LlmProvider p) {
    if (p.id != ProviderPresets.deepinfra.id) return p;
    return p.copyWith(
      selectedModel: (p.selectedModel ?? '').isEmpty
          ? ProviderPresets.defaultModel
          : p.selectedModel,
      thinkingModel: (p.thinkingModel ?? '').isEmpty
          ? ProviderPresets.defaultThinkingModel
          : p.thinkingModel,
    );
  }

  AppSettingsNotifier get _settings => ref.read(appSettingsProvider.notifier);

  SecretStore get _secrets => ref.read(secretStoreProvider);
}
