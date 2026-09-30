import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../device/data/device_providers.dart';
import '../../device/domain/device_config.dart';
import '../data/llm_providers.dart';
import '../data/providers_config_notifier.dart';

part 'provider_detail_ui.freezed.dart';
part 'provider_detail_ui.g.dart';

@freezed
abstract class ProviderDetailState with _$ProviderDetailState {
  const factory ProviderDetailState({
    String? selectedModel,
    @Default(false) bool isTesting,
    String? testReply,
    int? testMs,
    @Default(false) bool isPushing,

    /// The board's masked config after a push, as confirmation.
    DeviceConfig? pushed,
    String? error,
  }) = _ProviderDetailState;
}

/// Everything the detail screen holds beyond the provider itself: which
/// model is picked, and the results of test and push.
@riverpod
class ProviderDetailUi extends _$ProviderDetailUi {
  @override
  ProviderDetailState build(String providerId) {
    // Read once. Watching would rebuild this state when "Use on Orion"
    // saves the model, wiping the test reply mid-screen.
    final saved = ref
        .read(providersConfigProvider)
        .providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    return ProviderDetailState(selectedModel: saved?.selectedModel);
  }

  void pickModel(String id) => state = state.copyWith(
    selectedModel: id,
    testReply: null,
    testMs: null,
    pushed: null,
    error: null,
  );

  Future<void> saveEndpoint({required String baseUrl, String? apiKey}) async {
    final config = ref.read(providersConfigProvider.notifier);
    final current = ref
        .read(providersConfigProvider)
        .providers
        .where((p) => p.id == providerId)
        .firstOrNull;
    if (current == null) return;
    final trimmed = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    if (trimmed != current.baseUrl) {
      await config.upsert(current.copyWith(baseUrl: trimmed));
    }
    if (apiKey != null && apiKey.isNotEmpty) {
      await config.setApiKey(providerId, apiKey);
    }
  }

  Future<void> fetchModels({required String baseUrl, String? apiKey}) async {
    await saveEndpoint(baseUrl: baseUrl, apiKey: apiKey);
    ref.invalidate(modelListProvider(providerId));
  }

  Future<void> test() async {
    final model = state.selectedModel;
    if (model == null) return;
    state = state.copyWith(isTesting: true, error: null, testReply: null);
    final clock = Stopwatch()..start();
    final result = await ref
        .read(providersConfigProvider.notifier)
        .testModel(providerId, model);
    clock.stop();
    state = switch (result) {
      Ok(:final value) => state.copyWith(
        isTesting: false,
        // Some models answer one word per line; the card wants a sentence.
        testReply: value.replaceAll(RegExp(r'\s+'), ' ').trim(),
        testMs: clock.elapsedMilliseconds,
      ),
      Err(:final failure) => state.copyWith(
        isTesting: false,
        error: failure.message,
      ),
    };
  }

  Future<void> useOnDevice() async {
    final model = state.selectedModel;
    if (model == null) return;
    state = state.copyWith(isPushing: true, error: null, pushed: null);
    final result = await ref
        .read(providersConfigProvider.notifier)
        .useOnDevice(providerId, model);
    if (result case Err(:final failure)) {
      state = state.copyWith(isPushing: false, error: failure.message);
      return;
    }
    final config = await ref.read(deviceClientProvider).config();
    state = state.copyWith(isPushing: false, pushed: config.valueOrNull);
  }
}
