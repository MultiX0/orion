import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/storage/app_settings.dart';
import 'package:orion/core/storage/in_memory_settings_store.dart';
import 'package:orion/core/storage/storage_providers.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/providers/data/providers_config_notifier.dart';
import 'package:orion/features/providers/domain/fish_config.dart';
import 'package:orion/features/providers/domain/provider_presets.dart';
import 'package:orion/features/providers/domain/voice_presets.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  Future<ProviderContainer> load(AppSettings saved) async {
    final container = ProviderContainer(
      overrides: [
        useFakesProvider.overrideWithValue(true),
        settingsStoreProvider.overrideWithValue(InMemorySettingsStore(saved)),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appSettingsProvider.future);
    return container;
  }

  test('a Fish voice saved by an older build loads as Orion Voice', () async {
    final container = await load(
      const AppSettings(
        fish: FishConfig(voiceId: 'someone-else', ttsModel: 's1'),
      ),
    );
    final fish = container.read(providersConfigProvider).fish;
    expect(fish.voiceId, VoicePresets.orionVoiceId);
    expect(fish.ttsModel, 's1', reason: 'only the voice is pinned');
  });

  test('DeepInfra saved with no model comes back on Gemma', () async {
    final container = await load(
      AppSettings(
        providers: [
          ProviderPresets.deepinfra.copyWith(selectedModel: null),
          ProviderPresets.openai,
        ],
      ),
    );
    final config = container.read(providersConfigProvider);
    expect(config.selectedId, ProviderPresets.deepinfra.id);
    expect(config.selected?.selectedModel, ProviderPresets.defaultModel);
    expect(
      config.providers.firstWhere((p) => p.id == 'openai').selectedModel,
      isNull,
      reason: 'only DeepInfra has a default',
    );
  });

  test('no saved Fish block still means Orion Voice', () async {
    final container = await load(const AppSettings());
    expect(
      container.read(providersConfigProvider).fish.voiceId,
      VoicePresets.orionVoiceId,
    );
  });
}
