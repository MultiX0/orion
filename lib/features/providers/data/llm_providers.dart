import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/use_fakes.dart';
import '../../device/data/device_providers.dart';
import '../../harness/data/dsh_paths_provider.dart';
import '../domain/fish_repository.dart';
import '../domain/model_info.dart';
import '../domain/provider_repository.dart';
import 'fake_fish_repository.dart';
import 'fake_provider_repository.dart';
import 'http_fish_repository.dart';
import 'http_provider_repository.dart';
import 'providers_config_notifier.dart';

part 'llm_providers.g.dart';

@Riverpod(keepAlive: true)
ProviderRepository providerRepository(Ref ref) {
  if (ref.watch(useFakesProvider)) return FakeProviderRepository();
  return HttpProviderRepository(
    deviceClient: ref.watch(deviceClientProvider),
    harnessMirror: ref.watch(harnessMirrorProvider),
  );
}

@Riverpod(keepAlive: true)
FishRepository fishRepository(Ref ref) {
  if (ref.watch(useFakesProvider)) return FakeFishRepository();
  return HttpFishRepository(deviceClient: ref.watch(deviceClientProvider));
}

/// Models for one provider, with its key attached from the SecretStore.
/// Invalidate to fetch again.
@riverpod
Future<List<ModelInfo>> modelList(Ref ref, String providerId) async {
  final provider = ref.watch(
    providersConfigProvider.select(
      (c) => c.providers.where((p) => p.id == providerId).firstOrNull,
    ),
  );
  if (provider == null) throw const NotFoundFailure('Unknown provider');
  final key = await ref
      .watch(secretStoreProvider)
      .read(SecretKeys.providerApiKey(providerId));
  final result = await ref
      .watch(providerRepositoryProvider)
      .listModels(provider.copyWith(apiKey: key));
  return result.getOrThrow();
}
