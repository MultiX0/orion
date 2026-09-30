import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/use_fakes.dart';
import '../../device/domain/device.dart';
import '../domain/device_discovery.dart';
import '../domain/pairing_repository.dart';
import 'fake_device_discovery.dart';
import 'fake_pairing_repository.dart';
import 'http_pairing_repository.dart';
import 'lan_device_discovery.dart';

part 'onboarding_providers.g.dart';

@Riverpod(keepAlive: true)
DeviceDiscovery deviceDiscovery(Ref ref) {
  if (ref.watch(useFakesProvider)) return FakeDeviceDiscovery();
  // A board we paired with before answers orion-<last4>.local, which is the
  // fastest of the four sources when it works.
  return LanDeviceDiscovery(knownDeviceId: ref.watch(pairedDeviceProvider)?.id);
}

@Riverpod(keepAlive: true)
PairingRepository pairingRepository(Ref ref) {
  if (ref.watch(useFakesProvider)) return FakePairingRepository();
  return HttpPairingRepository(
    secrets: ref.watch(secretStoreProvider),
    discovery: ref.watch(deviceDiscoveryProvider),
  );
}

/// Boards seen so far. Auto-disposes, so leaving the screen stops the search.
@riverpod
Stream<List<Device>> discoveredDevices(Ref ref) =>
    ref.watch(deviceDiscoveryProvider).discover();

/// Runs the provision call and records the result as the paired device.
@Riverpod(name: 'pairingProvider')
class PairingNotifier extends _$PairingNotifier {
  @override
  Future<Device?> build() async => null;

  Future<void> pair({
    required String host,
    required String wifiSsid,
    required String wifiPassword,
    required String deviceName,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .read(pairingRepositoryProvider)
        .pair(
          host: host,
          wifiSsid: wifiSsid,
          wifiPassword: wifiPassword,
          deviceName: deviceName,
        );
    switch (result) {
      case Ok(:final value):
        await ref.read(appSettingsProvider.notifier).setPairedDevice(value);
        state = AsyncData(value);
      case Err(:final failure):
        state = AsyncError(failure, StackTrace.current);
    }
  }

  /// Code pairing, first half: the board puts six digits on its screen.
  /// True when it did; false means the access point form is the way in.
  Future<bool?> requestCode(String host) async {
    state = const AsyncLoading();
    final result = await ref
        .read(pairingRepositoryProvider)
        .requestCode(host: host);
    switch (result) {
      case Ok(:final value):
        state = const AsyncData(null);
        return value;
      case Err(:final failure):
        state = AsyncError(failure, StackTrace.current);
        return null;
    }
  }

  /// Code pairing, second half. Success is recorded the same way pair()
  /// records one, so the journey moves on the same way.
  Future<void> pairWithCode({
    required String host,
    required String code,
  }) async {
    state = const AsyncLoading();
    final result = await ref
        .read(pairingRepositoryProvider)
        .pairWithCode(host: host, code: code);
    switch (result) {
      case Ok(:final value):
        await ref.read(appSettingsProvider.notifier).setPairedDevice(value);
        state = AsyncData(value);
      case Err(:final failure):
        state = AsyncError(failure, StackTrace.current);
    }
  }

  /// A board paired over Bluetooth and found again on the LAN. Recorded the
  /// same way pair() records one, so the journey moves on the same way.
  Future<void> adopt(Device device) async {
    await ref.read(appSettingsProvider.notifier).setPairedDevice(device);
    state = AsyncData(device);
  }

  /// Manual entry: confirm a typed address answers /api/info. The caller then
  /// takes the board to the pair step, because a board that was provisioned
  /// before wants a token on everything else and only pair() hands one over.
  Future<Device?> probeAddress(String host) async {
    state = const AsyncLoading();
    final result = await ref.read(deviceDiscoveryProvider).probe(host);
    switch (result) {
      case Ok(:final value):
        state = const AsyncData(null);
        return value;
      case Err(:final failure):
        state = AsyncError(failure, StackTrace.current);
        return null;
    }
  }
}
