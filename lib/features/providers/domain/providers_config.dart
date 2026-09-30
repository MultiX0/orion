import 'package:freezed_annotation/freezed_annotation.dart';

import 'fish_config.dart';
import 'llm_provider.dart';

part 'providers_config.freezed.dart';

/// What the Providers screen edits: the provider list, which one the board
/// uses, and the Fish Audio block.
@freezed
abstract class ProvidersConfig with _$ProvidersConfig {
  const ProvidersConfig._();

  const factory ProvidersConfig({
    @Default(<LlmProvider>[]) List<LlmProvider> providers,
    String? selectedId,
    @Default(FishConfig()) FishConfig fish,
  }) = _ProvidersConfig;

  LlmProvider? get selected =>
      providers.where((p) => p.id == selectedId).firstOrNull;
}
