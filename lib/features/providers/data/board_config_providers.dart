import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/use_fakes.dart';
import '../../device/data/device_providers.dart';
import '../../onboarding/data/bluetooth_providers.dart';
import '../domain/board_config_repository.dart';
import 'http_board_config_repository.dart';
import 'llm_providers.dart';
import 'stage_setup.dart';

part 'board_config_providers.g.dart';

@Riverpod(keepAlive: true)
BoardConfigRepository boardConfigRepository(Ref ref) {
  if (ref.watch(useFakesProvider)) return FakeBoardConfigRepository();
  return HttpBoardConfigRepository(
    api: ref.watch(deviceApiProvider),
    secrets: ref.watch(secretStoreProvider),
    bluetooth: ref.watch(provisioningRepositoryProvider),
  );
}

/// One stage's Test: send that block if it changed, since the board tests
/// what it has stored, then ask the board to try it.
@riverpod
class StageTest extends _$StageTest {
  @override
  AsyncValue<StageTestResult?> build(String stage) => const AsyncData(null);

  Future<void> run() async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    final sent = await ref
        .read(stageSetupProvider.notifier)
        .send(stages: [stage]);
    if (!ref.mounted) return;
    if (sent case Err(:final failure)) {
      state = AsyncError(failure, StackTrace.current);
      return;
    }
    for (var attempt = 0; ; attempt++) {
      final result = await ref.read(boardConfigRepositoryProvider).test(stage);
      if (!ref.mounted) return;
      final busy = result.valueOrNull?.error == busyError;
      if (busy && attempt < busyRetries) {
        // Shown as "Orion is talking, trying again" while the turn ends.
        state = AsyncData(result.valueOrNull);
        await Future<void>.delayed(busyWait);
        if (!ref.mounted) return;
        continue;
      }
      state = switch (result) {
        Ok(:final value) => AsyncData(value),
        Err(:final failure) => AsyncError(failure, StackTrace.current),
      };
      return;
    }
  }

  /// A turn takes a few seconds; half a minute of patience covers any.
  static const busyRetries = 15;
  static const busyWait = Duration(seconds: 2);
  static const busyError = HttpBoardConfigRepository.busyError;
}

/// The Fish account's API credit in dollars, or null when there is no key
/// or Fish would not say. Invalidate after a new key is stored.
@riverpod
Future<double?> fishCredit(Ref ref) async {
  final key = await ref.watch(secretStoreProvider).read(SecretKeys.fishApiKey);
  if (key == null || key.isEmpty) return null;
  final credit = await ref.watch(fishRepositoryProvider).apiCredit(key);
  return credit.valueOrNull;
}
