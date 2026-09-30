import 'dart:async';

import 'package:riverpod/riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../domain/connection_status.dart';
import '../domain/device_mode.dart';
import '../domain/device_state.dart';
import '../domain/ws_event.dart';
import 'device_providers.dart';

part 'device_state_notifier.g.dart';

/// The board state as the app knows it: the last full read from /api/state
/// with socket deltas merged on top. Widgets select single fields from it.
@Riverpod(keepAlive: true, name: 'deviceStateProvider')
class DeviceStateNotifier extends _$DeviceStateNotifier {
  @override
  DeviceState build() {
    ref.listen(deviceEventsProvider, (_, next) {
      final event = next.value;
      if (event is WsStateEvent) _merge(event);
    });
    ref.listen(
      connectionStatusProvider,
      (_, next) => _onConnection(next.value),
    );
    return const DeviceState();
  }

  void _onConnection(ConnectionStatus? status) {
    switch (status) {
      case ConnectionStatus.connected:
        unawaited(_refresh());
      case ConnectionStatus.disconnected:
      case ConnectionStatus.reconnecting:
        state = state.copyWith(mode: DeviceMode.offline);
      case ConnectionStatus.connecting:
      case null:
        break;
    }
  }

  Future<void> _refresh() async {
    final result = await ref.read(deviceClientProvider).state();
    final fresh = result.valueOrNull;
    if (fresh != null && ref.mounted) state = fresh;
  }

  void _merge(WsStateEvent event) {
    state = state.copyWith(
      mode: event.mode ?? state.mode,
      wifiRssi: event.wifiRssi ?? state.wifiRssi,
      volume: event.volume ?? state.volume,
      muted: event.muted ?? state.muted,
      wakeWordEnabled: event.wakeWordEnabled ?? state.wakeWordEnabled,
      level: event.level,
      error: event.error,
    );
  }
}

/// Only the mode. The orb watches this so RSSI ticks never repaint it.
@riverpod
DeviceMode deviceMode(Ref ref) =>
    ref.watch(deviceStateProvider.select((s) => s.mode));
