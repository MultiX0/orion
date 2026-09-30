import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:orion/features/providers/data/providers_config_notifier.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/model_info.dart';
import 'package:orion/features/providers/presentation/model_picker_results.dart';
import 'package:orion/features/providers/presentation/stages/mind_card.dart';

/// The fake list, except it never arrives.
class _FailingRepository extends FakeProviderRepository {
  _FailingRepository(this.failure);

  final Failure failure;

  @override
  Future<Result<List<ModelInfo>>> listModels(LlmProvider provider) async =>
      Err(failure);
}

const _desktop = PlatformInfo(
  isMobile: false,
  isDesktop: true,
  canHostHarness: true,
  hasTouch: false,
  osName: 'windows',
);

const _phone = PlatformInfo(
  isMobile: true,
  isDesktop: false,
  canHostHarness: false,
  hasTouch: true,
  osName: 'android',
);

void main() {
  const gemma = 'google/gemma-4-31B-it-turbo';

  Future<void> pump(
    WidgetTester tester, {
    PlatformInfo platform = _desktop,
    Failure? failure,
  }) async {
    await tester.binding.setSurfaceSize(const Size(900, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useFakesProvider.overrideWithValue(true),
          secretStoreProvider.overrideWithValue(InMemorySecretStore()),
          platformInfoProvider.overrideWithValue(platform),
          if (failure != null)
            providerRepositoryProvider.overrideWithValue(
              _FailingRepository(failure),
            ),
        ],
        child: MaterialApp(
          theme: buildOrionTheme(),
          home: const Scaffold(
            body: SingleChildScrollView(child: MindCard(canTest: false)),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text(gemma));
    await settle(tester);
  }

  String? chosen(WidgetTester tester) => ProviderScope.containerOf(
    tester.element(find.byType(MindCard)),
  ).read(providersConfigProvider).selected?.selectedModel;

  testWidgets('DeepInfra opens on Gemma, and the list hides non-chat models', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text(gemma), findsOneWidget);
    await open(tester);
    expect(find.text('Pick a model'), findsOneWidget);
    expect(find.text('deepseek-ai/DeepSeek-V3'), findsOneWidget);
    expect(find.text('BAAI/bge-m3'), findsNothing, reason: 'an embedding');
  });

  testWidgets('search filters as you type, in any case', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField).last, 'QWEN');
    await tester.pump();
    expect(find.text('Qwen/Qwen2.5-VL-72B-Instruct'), findsOneWidget);
    expect(find.text('deepseek-ai/DeepSeek-V3'), findsNothing);
    expect(find.text('Use QWEN'), findsOneWidget);
  });

  testWidgets('tapping a model picks it and closes the picker', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('deepseek-ai/DeepSeek-V3'));
    await settle(tester);
    expect(find.text('Pick a model'), findsNothing);
    expect(chosen(tester), 'deepseek-ai/DeepSeek-V3');
    expect(find.text('deepseek-ai/DeepSeek-V3'), findsOneWidget);
  });

  testWidgets('Enter takes the first match', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.enterText(find.byType(TextField).last, 'llama');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(chosen(tester), 'meta-llama/Llama-3.3-70B-Instruct-Turbo');
  });

  testWidgets('Escape closes without changing the model', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.text('Pick a model'), findsNothing);
    expect(chosen(tester), gemma);
  });

  testWidgets('a list that fails says why and takes the typed id', (
    tester,
  ) async {
    await pump(
      tester,
      failure: const ProviderFailure(ProviderFailureKind.network, 'offline'),
    );
    await open(tester);
    expect(find.text('This device could not reach DeepInfra.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'my-org/my-model');
    await tester.pump();
    await tester.tap(find.text('Use my-org/my-model'));
    await settle(tester);
    expect(chosen(tester), 'my-org/my-model');
  });

  testWidgets('Enter uses the typed id when the list failed', (tester) async {
    await pump(
      tester,
      failure: const ProviderFailure(ProviderFailureKind.badKey, 'no'),
    );
    await open(tester);
    expect(
      find.text('There is no DeepInfra key on this device yet.'),
      findsOneWidget,
    );
    await tester.enterText(find.byType(TextField).last, 'typed/model');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settle(tester);
    expect(chosen(tester), 'typed/model');
  });

  testWidgets('a phone gets a bottom sheet instead of a dialog', (
    tester,
  ) async {
    await pump(tester, platform: _phone);
    await open(tester);
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.text('Pick a model'), findsOneWidget);
  });

  test('the filter matches id or name and drops known non-chat models', () {
    const models = [
      ModelInfo(id: 'a/Chat-One', supportsChat: true),
      ModelInfo(id: 'b/two', displayName: 'Friendly Two'),
      ModelInfo(id: 'c/embed', supportsChat: false),
    ];
    List<String> ids(String q) =>
        filterModels(models, q).map((m) => m.id).toList();
    expect(ids(''), ['a/Chat-One', 'b/two']);
    expect(ids('chat'), ['a/Chat-One']);
    expect(ids('FRIENDLY'), ['b/two']);
    expect(ids('embed'), isEmpty);
  });

  test('the chosen model leads until something is typed', () {
    const models = [
      ModelInfo(id: 'a/one'),
      ModelInfo(id: 'b/two'),
      ModelInfo(id: 'c/three'),
    ];
    List<String> ids(String q) =>
        pickerRows(models, q, 'c/three').map((m) => m.id).toList();
    expect(ids(''), ['c/three', 'a/one', 'b/two']);
    expect(ids('o'), ['a/one', 'b/two'], reason: 'a search keeps list order');
  });

  test('bad key reads as a turned-down key once one is on file', () {
    const failure = ProviderFailure(ProviderFailureKind.badKey, 'no');
    expect(
      modelListProblem(failure, name: 'OpenAI', hasKey: true),
      'OpenAI turned down the key on file.',
    );
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
