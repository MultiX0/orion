import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/storage_providers.dart';
import '../../device/data/device_providers.dart';
import '../../device/domain/device_config.dart';
import '../domain/device_settings.dart';

part 'device_settings_notifier.g.dart';

/// Reads info and config from the board and writes edits back as partial
/// config patches. Edits show at once and roll back if the board says no.
@Riverpod(name: 'deviceSettingsProvider')
class DeviceSettingsNotifier extends _$DeviceSettingsNotifier {
  @override
  Future<DeviceSettings> build() async {
    final client = ref.watch(deviceClientProvider);
    final info = (await client.info()).getOrThrow();
    final config = (await client.config()).getOrThrow();
    return DeviceSettings(
      name: config.deviceName ?? info.name,
      volume: config.volume ?? 0,
      wakeWordEnabled: config.wakeWordEnabled ?? true,
      language: config.language ?? 'en',
      timeZone: config.timeZone,
      deviceId: info.deviceId,
      fwVersion: info.fwVersion,
      ip: info.ip,
      hasCamera: info.hasCamera,
      uptimeS: info.uptimeS,
    );
  }

  Future<void> setVolume(int volume) =>
      _patch(DeviceConfig(volume: volume), (s) => s.copyWith(volume: volume));

  Future<void> setWakeWord(bool enabled) => _patch(
    DeviceConfig(wakeWordEnabled: enabled),
    (s) => s.copyWith(wakeWordEnabled: enabled),
  );

  Future<void> setTimeZone(String tz) =>
      _patch(DeviceConfig(timeZone: tz), (s) => s.copyWith(timeZone: tz));

  Future<void> setName(String name) =>
      _patch(DeviceConfig(deviceName: name), (s) => s.copyWith(name: name));

  Future<void> setLanguage(String language) => _patch(
    DeviceConfig(language: language),
    (s) => s.copyWith(language: language),
  );

  Future<Result<void>> restart() => ref.read(deviceClientProvider).restart();

  Future<void> unpair() async {
    // Forget first. With the board out of reach, stopping the socket can wait
    // on a connect that never finishes, and the pairing must go either way.
    final client = ref.read(deviceClientProvider);
    await ref.read(appSettingsProvider.notifier).setPairedDevice(null);
    try {
      await client.disconnect().timeout(const Duration(seconds: 2));
    } on Object {
      // Nothing to close cleanly; the client goes with the pairing.
    }
  }

  Future<void> _patch(
    DeviceConfig patch,
    DeviceSettings Function(DeviceSettings current) apply,
  ) async {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(apply(current));
    final result = await ref.read(deviceClientProvider).updateConfig(patch);
    if (result.isErr && ref.mounted) state = AsyncData(current);
  }
}
