import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../onboarding/data/bluetooth_providers.dart';

part 'change_wifi.freezed.dart';
part 'change_wifi.g.dart';

@freezed
abstract class ChangeWifiState with _$ChangeWifiState {
  const factory ChangeWifiState({
    /// The user took the Bluetooth path instead of the LAN.
    @Default(false) bool bluetooth,
    @Default(false) bool busy,
    Failure? error,

    /// The network the board agreed to move to over the LAN.
    String? movedTo,
  }) = _ChangeWifiState;
}

/// Change Wi-Fi for the paired board: over the LAN while it is online,
/// over Bluetooth when it is out of reach and in setup mode.
@riverpod
class ChangeWifi extends _$ChangeWifi {
  @override
  ChangeWifiState build() => const ChangeWifiState();

  void useBluetooth() => state = state.copyWith(bluetooth: true, error: null);

  Future<void> send({required String ssid, required String password}) async {
    if (state.busy) return;
    state = state.copyWith(busy: true, error: null, movedTo: null);
    final result = await ref
        .read(wifiChangeRepositoryProvider)
        .changeOverLan(ssid: ssid, password: password);
    if (!ref.mounted) return;
    state = switch (result) {
      Ok() => state.copyWith(busy: false, movedTo: ssid.trim()),
      Err(:final failure) => state.copyWith(busy: false, error: failure),
    };
  }
}
