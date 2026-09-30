import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/platform/platform_info.dart';
import '../../../core/storage/storage_providers.dart';
import '../../../core/use_fakes.dart';
import '../../device/data/device_providers.dart';
import '../domain/provisioning_repository.dart';
import '../domain/wifi_change_repository.dart';
import 'ble/ble_provisioning_repository.dart';
import 'ble/esp_provisioning_link.dart';
import 'ble/fake_provisioning_link.dart';
import 'ble/provisioning_link.dart';
import 'ble/unsupported_link.dart';
import 'http_wifi_change_repository.dart';
import 'lan_handover.dart';
import 'onboarding_providers.dart';

part 'bluetooth_providers.g.dart';

/// `--dart-define=ORION_FAKE_BLE=true` puts the scripted board behind the
/// Bluetooth path on any platform. It reports the mock's address as its
/// own, so a desktop walks the whole flow and lands paired with the mock.
const fakeBluetooth = bool.fromEnvironment('ORION_FAKE_BLE');

@Riverpod(keepAlive: true)
ProvisioningLink provisioningLink(Ref ref) {
  if (fakeBluetooth) {
    return FakeProvisioningLink(ip: 'localhost:${ApiPaths.mockPort}');
  }
  if (ref.watch(useFakesProvider)) return FakeProvisioningLink();
  if (ref.watch(platformInfoProvider).canUseBluetooth) {
    return EspProvisioningLink();
  }
  return UnsupportedLink();
}

@Riverpod(keepAlive: true)
ProvisioningRepository provisioningRepository(Ref ref) =>
    BleProvisioningRepository(
      link: ref.watch(provisioningLinkProvider),
      secrets: ref.watch(secretStoreProvider),
    );

@riverpod
LanHandover lanHandover(Ref ref) =>
    LanHandover(discovery: ref.watch(deviceDiscoveryProvider));

@riverpod
WifiChangeRepository wifiChangeRepository(Ref ref) {
  if (ref.watch(useFakesProvider)) return FakeWifiChangeRepository();
  return HttpWifiChangeRepository(
    api: ref.watch(deviceApiProvider),
    secrets: ref.watch(secretStoreProvider),
  );
}
