import '../../../core/result.dart';
import '../../device/domain/device.dart';
import '../domain/pairing_repository.dart';

/// Waits about as long as a real board takes to reboot, then succeeds.
class FakePairingRepository implements PairingRepository {
  @override
  Future<Result<bool>> requestCode({required String host}) async =>
      const Ok(true);

  @override
  Future<Result<Device>> pairWithCode({
    required String host,
    required String code,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (code.trim() != '123456') {
      return const Err(
        AuthFailure("That is not the code on Orion's screen. 4 tries left."),
      );
    }
    return Ok(
      Device(id: 'orion-a1b2', name: 'Orion', host: host, fwVersion: '0.1.0'),
    );
  }

  @override
  Future<Result<Device>> pair({
    required String host,
    required String wifiSsid,
    required String wifiPassword,
    required String deviceName,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    if (wifiSsid.trim().isEmpty) {
      return const Err(DeviceFailure('bad_ssid', 'Wi-Fi name cannot be empty'));
    }
    return Ok(
      Device(
        id: 'orion-a1b2',
        name: deviceName.trim().isEmpty ? 'Orion' : deviceName.trim(),
        host: host,
        fwVersion: '0.1.0',
      ),
    );
  }
}
