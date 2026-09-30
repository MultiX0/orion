import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/platform/platform_info.dart';
import 'package:orion/core/result.dart';
import 'package:orion/core/storage/in_memory_secret_store.dart';
import 'package:orion/core/storage/storage_providers.dart';
import 'package:orion/core/theme/theme.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/providers/data/fake_provider_repository.dart';
import 'package:orion/features/providers/data/llm_providers.dart';
import 'package:orion/features/providers/data/stage_setup.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/model_info.dart';
import 'package:orion/features/providers/domain/voice_stages.dart';
import 'package:orion/features/providers/presentation/speech_models.dart';
import 'package:orion/features/providers/presentation/stages/listen_card.dart';
import 'package:orion/features/providers/presentation/stages/speak_card.dart';

/// The fake list, except it never arrives.
class _FailingRepository extends FakeProviderRepository {
  @override
  Future<Result<List<ModelInfo>>> listModels(LlmProvider provider) async =>
      const Err(ProviderFailure(ProviderFailureKind.network, 'offline'));
}

const _desktop = PlatformInfo(
  isMobile: false,
  isDesktop: true,
  canHostHarness: true,
  hasTouch: false,
  osName: 'windows',
);

void main() {
  Future<void> pump(
    WidgetTester tester,
    Widget card, {
    bool failing = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useFakesProvider.overrideWithValue(true),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          platformInfoProvider.overrideWithValue(_desktop),
          if (failing)
            providerRepositoryProvider.overrideWithValue(_FailingRepository()),
        ],
        child: MaterialApp(
          theme: buildOrionTheme(),
          home: Scaffold(body: SingleChildScrollView(child: card)),
        ),
      ),
    );
    await settle(tester);
  }

  VoiceStages stages(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(Scaffold)),
  ).read(voiceStagesProvider);

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).last);
    await settle(tester);
  }

  testWidgets('DeepInfra listening offers only its speech to text models', (
    tester,
  ) async {
    await pump(tester, const ListenCard(canTest: false));
    await tap(tester, 'DeepInfra');
    expect(find.text('Qwen/Qwen3-ASR-1.7B'), findsOneWidget, reason: 'default');
    await tap(tester, 'Qwen/Qwen3-ASR-1.7B');
    expect(find.text('Pick a model'), findsOneWidget);
    expect(find.text('openai/whisper-large-v3-turbo'), findsOneWidget);
    expect(find.text('Qwen/Qwen3-TTS'), findsNothing);
    expect(find.text('hexgrad/Kokoro-82M'), findsNothing);
    expect(find.text('google/gemma-4-31B-it-turbo'), findsNothing);
    expect(find.text('BAAI/bge-m3'), findsNothing);
    await tap(tester, 'openai/whisper-large-v3-turbo');
    expect(find.text('Pick a model'), findsNothing);
    expect(stages(tester).stt.model, 'openai/whisper-large-v3-turbo');
  });

  testWidgets('OpenAI listening goes by id', (tester) async {
    await pump(tester, const ListenCard(canTest: false));
    await tap(tester, 'OpenAI');
    await tap(tester, 'gpt-4o-mini-transcribe');
    expect(find.text('whisper-1'), findsOneWidget);
    expect(find.text('gpt-4o-mini-transcribe'), findsNWidgets(2));
    expect(find.text('gpt-4o'), findsNothing);
    expect(find.text('gpt-4o-mini-tts'), findsNothing);
    expect(find.text('tts-1'), findsNothing);
  });

  testWidgets('DeepInfra speaking picks a text to speech model', (
    tester,
  ) async {
    await pump(tester, const SpeakCard(canTest: false));
    await tap(tester, 'DeepInfra');
    expect(find.text('Qwen/Qwen3-TTS'), findsOneWidget, reason: 'default');
    await tap(tester, 'Qwen/Qwen3-TTS');
    expect(find.text('Qwen/Qwen3-ASR-1.7B'), findsNothing);
    expect(find.text('deepseek-ai/DeepSeek-V3'), findsNothing);
    await tap(tester, 'hexgrad/Kokoro-82M');
    expect(find.text('Pick a model'), findsNothing);
    expect(stages(tester).tts.model, 'hexgrad/Kokoro-82M');
    expect(find.text('// VOICE'), findsOneWidget, reason: 'still typed');
  });

  testWidgets('a custom endpoint that does not say shows everything', (
    tester,
  ) async {
    await pump(tester, const SpeakCard(canTest: false));
    await tap(tester, 'Custom');
    await tester.enterText(
      find.byType(TextField).first,
      'http://localhost:8000/v1/',
    );
    await settle(tester);
    await tap(tester, 'Pick a model');
    expect(find.text('// MODEL · LOCALHOST'), findsOneWidget);
    await tap(tester, 'local-model');
    expect(stages(tester).tts.model, 'local-model');
    expect(stages(tester).tts.baseUrl, 'http://localhost:8000/v1/');
  });

  testWidgets('a list that fails still takes a typed model', (tester) async {
    await pump(tester, const ListenCard(canTest: false), failing: true);
    await tap(tester, 'DeepInfra');
    await tap(tester, 'Qwen/Qwen3-ASR-1.7B');
    expect(find.text('This device could not reach DeepInfra.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'my-org/my-asr');
    await tester.pump();
    await tap(tester, 'Use my-org/my-asr');
    expect(stages(tester).stt.model, 'my-org/my-asr');
  });

  test('the speech filter trusts tags, then ids, then shows everything', () {
    bool fits(ModelInfo m, String stage, String preset) =>
        fitsSpeechStage(m, stage: stage, presetId: preset);
    const tagged = ModelInfo(
      id: 'openai/whisper-large-v3',
      supportsSpeechToText: true,
      supportsTextToSpeech: false,
    );
    const chat = ModelInfo(id: 'gpt-4o');
    expect(fits(tagged, Stage.stt, 'deepinfra'), isTrue);
    expect(fits(tagged, Stage.tts, 'deepinfra'), isFalse);
    expect(fits(chat, Stage.stt, 'deepinfra'), isFalse, reason: 'no tag');
    expect(fits(const ModelInfo(id: 'whisper-1'), Stage.stt, 'openai'), isTrue);
    expect(fits(const ModelInfo(id: 'tts-1-hd'), Stage.tts, 'openai'), isTrue);
    expect(
      fits(const ModelInfo(id: 'gpt-4o-mini-tts'), Stage.tts, 'openai'),
      isTrue,
    );
    expect(fits(chat, Stage.stt, 'openai'), isFalse);
    expect(fits(chat, Stage.tts, 'openai'), isFalse);
    expect(
      fits(const ModelInfo(id: 'whisper-large-v3'), Stage.stt, 'groq'),
      isTrue,
    );
    expect(fits(chat, Stage.stt, 'custom'), isTrue, reason: 'it did not say');
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
