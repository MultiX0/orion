import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/storage/storage_providers.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/device/data/device_providers.dart';
import 'package:orion/features/device/domain/device_config.dart';
import 'package:orion/features/settings/data/time_zone_sync.dart';
import 'package:riverpod/riverpod.dart';

void main() {
  late ProviderContainer container;

  setUp(() {
    container = ProviderContainer(
      overrides: [useFakesProvider.overrideWithValue(true)],
    );
    addTearDown(container.dispose);
  });

  Future<String?> boardZone() async =>
      (await container.read(deviceClientProvider).config())
          .getOrThrow()
          .timeZone;

  test('on automatic, the board takes this device\'s zone', () async {
    expect(await boardZone(), 'UTC0');
    await container.read(timeZoneSyncProvider.notifier).sync();
    expect(await boardZone(), TimeZoneSync.here());
  });

  test('a zone picked by hand is left alone', () async {
    await container.read(appSettingsProvider.notifier).setTimeZoneAuto(false);
    await container
        .read(deviceClientProvider)
        .updateConfig(const DeviceConfig(timeZone: '<+0530>-5:30'));
    await container.read(timeZoneSyncProvider.notifier).sync();
    expect(await boardZone(), '<+0530>-5:30');
  });
}
