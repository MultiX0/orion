import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/storage/app_settings.dart';
import 'package:orion/core/storage/prefs_settings_store.dart';
import 'package:orion/features/device/domain/device.dart';
import 'package:orion/features/providers/domain/fish_config.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  test('an empty store loads the defaults', () async {
    final settings = await PrefsSettingsStore().load();
    expect(settings.isPaired, isFalse);
    expect(settings.providers, isEmpty);
    expect(settings.reducedMotion, isFalse);
  });

  test('a saved settings blob comes back whole', () async {
    final store = PrefsSettingsStore();
    const settings = AppSettings(
      pairedDevice: Device(
        id: 'orion-a1b2',
        name: 'Orion',
        host: '192.168.1.40',
        fwVersion: '0.1.0',
      ),
      selectedProviderId: 'deepinfra',
      providers: [
        LlmProvider(
          id: 'deepinfra',
          kind: ProviderKind.deepinfra,
          name: 'DeepInfra',
          baseUrl: 'https://api.deepinfra.com/v1/openai',
          apiKey: 'sk-should-not-be-written',
          selectedModel: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
        ),
      ],
      fish: FishConfig(voiceId: 'orion-voice'),
    );

    await store.save(settings);
    final loaded = await PrefsSettingsStore().load();

    expect(loaded.pairedDevice, settings.pairedDevice);
    expect(loaded.selectedProviderId, 'deepinfra');
    expect(loaded.providers.single.selectedModel, contains('Llama'));
    expect(loaded.fish?.ttsModel, 's2.1-pro-free');
  });

  test('the api key never reaches the settings blob', () async {
    final store = PrefsSettingsStore();
    const settings = AppSettings(
      providers: [
        LlmProvider(
          id: 'openai',
          kind: ProviderKind.openai,
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: 'sk-live-secret',
        ),
      ],
    );

    await store.save(settings);
    final raw = jsonEncode(settings.toJson());

    expect(raw, isNot(contains('sk-live-secret')));
    expect((await store.load()).providers.single.apiKey, isNull);
  });

  test('a corrupt blob falls back to the defaults', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          PrefsSettingsStore.key: 'not json',
        });

    final settings = await PrefsSettingsStore().load();
    expect(settings, const AppSettings());
  });
}
