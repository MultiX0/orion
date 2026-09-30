import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../features/device/domain/device.dart';
import '../use_fakes.dart';
import 'app_settings.dart';
import 'in_memory_secret_store.dart';
import 'in_memory_settings_store.dart';
import 'prefs_settings_store.dart';
import 'secret_store.dart';
import 'secure_secret_store.dart';
import 'settings_store.dart';
import '../../features/harness/domain/approval_mode.dart';

part 'storage_providers.g.dart';

@Riverpod(keepAlive: true)
SecretStore secretStore(Ref ref) {
  if (ref.watch(useFakesProvider)) return InMemorySecretStore();
  return SecureSecretStore();
}

@Riverpod(keepAlive: true)
SettingsStore settingsStore(Ref ref) {
  if (ref.watch(useFakesProvider)) return InMemorySettingsStore.paired();
  return PrefsSettingsStore();
}

/// The single source of app-side settings. Every change is written through.
@Riverpod(keepAlive: true, name: 'appSettingsProvider')
class AppSettingsNotifier extends _$AppSettingsNotifier {
  @override
  Future<AppSettings> build() => ref.watch(settingsStoreProvider).load();

  Future<void> edit(AppSettings Function(AppSettings current) change) async {
    final next = change(await future);
    state = AsyncData(next);
    await ref.read(settingsStoreProvider).save(next);
  }

  Future<void> setPairedDevice(Device? device) =>
      edit((s) => s.copyWith(pairedDevice: device));

  Future<void> setReducedMotion(bool on) =>
      edit((s) => s.copyWith(reducedMotion: on));

  Future<void> setHarnessEnabled(bool on) =>
      edit((s) => s.copyWith(harnessEnabled: on));

  Future<void> setApprovalMode(ApprovalMode mode) =>
      edit((s) => s.copyWith(approvalMode: mode));

  Future<void> setTimeZoneAuto(bool on) =>
      edit((s) => s.copyWith(timeZoneAuto: on));
}

@Riverpod(keepAlive: true)
bool isPaired(Ref ref) =>
    ref.watch(appSettingsProvider.select((s) => s.value?.isPaired ?? false));

@Riverpod(keepAlive: true)
Device? pairedDevice(Ref ref) =>
    ref.watch(appSettingsProvider.select((s) => s.value?.pairedDevice));
