import 'package:freezed_annotation/freezed_annotation.dart';

part 'device_settings.freezed.dart';

/// The editable and read-only device fields the Settings screen shows,
/// merged from /api/info and /api/config.
@freezed
abstract class DeviceSettings with _$DeviceSettings {
  const factory DeviceSettings({
    required String name,
    required int volume,
    required bool wakeWordEnabled,
    required String language,

    /// As the board stores it, a POSIX TZ string. Null on older firmware.
    String? timeZone,
    required String deviceId,
    required String fwVersion,
    required String ip,
    @Default(false) bool hasCamera,
    @Default(0) int uptimeS,
  }) = _DeviceSettings;
}
