import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/storage/storage_providers.dart';
import '../../../core/time/posix_tz.dart';
import '../../device/data/device_providers.dart';
import '../../device/data/device_state_notifier.dart';
import '../../device/domain/device_config.dart';
import '../../device/domain/device_mode.dart';

part 'time_zone_sync.g.dart';

/// While the time zone is on automatic, keeps the board on this device's
/// zone. It checks each time the board comes back into reach, so a change to
/// summer time follows the next time an app sees the board.
@Riverpod(keepAlive: true)
class TimeZoneSync extends _$TimeZoneSync {
  @override
  void build() {
    ref.listen(deviceModeProvider, (previous, next) {
      final back =
          next != DeviceMode.offline &&
          (previous == null || previous == DeviceMode.offline);
      if (back) sync();
    }, fireImmediately: true);
  }

  /// This device's zone as the board takes it.
  static String here() => PosixTz.fromOffset(DateTime.now().timeZoneOffset);

  Future<void> sync() async {
    final settings = await ref.read(appSettingsProvider.future);
    if (!settings.isPaired || !settings.timeZoneAuto) return;
    final client = ref.read(deviceClientProvider);
    final config = await client.config();
    if (config.isErr) return;
    final want = here();
    if (config.getOrThrow().timeZone == want) return;
    await client.updateConfig(DeviceConfig(timeZone: want));
  }
}
