import 'package:freezed_annotation/freezed_annotation.dart';

import 'device_mode.dart';

part 'device_state.freezed.dart';
part 'device_state.g.dart';

/// GET /api/state, kept fresh by the WebSocket state events.
@freezed
abstract class DeviceState with _$DeviceState {
  const factory DeviceState({
    @Default(DeviceMode.offline) DeviceMode mode,
    @Default(0) int wifiRssi,
    int? batteryPct,
    @Default(0) int volume,
    @Default(true) bool wakeWordEnabled,
    @Default(false) bool muted,
    String? lastTurnId,
    String? error,

    /// Mic level 0..1 while listening, when the board sends it.
    double? level,
  }) = _DeviceState;

  factory DeviceState.fromJson(Map<String, dynamic> json) =>
      _$DeviceStateFromJson(json);
}
