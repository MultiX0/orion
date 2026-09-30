import '../../../core/network/api_paths.dart';
import '../../../core/network/device_api.dart';
import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../domain/wifi_change_repository.dart';

/// POST /api/provision on the paired board with its token. The same token
/// rides along in the body so a board that treats this as a fresh pairing
/// keeps the one the app already has.
class HttpWifiChangeRepository implements WifiChangeRepository {
  HttpWifiChangeRepository({required this.api, required this.secrets});

  final DeviceApi api;
  final SecretStore secrets;

  @override
  Future<Result<void>> changeOverLan({
    required String ssid,
    required String password,
  }) async {
    if (ssid.trim().isEmpty) {
      return const Err(DeviceFailure('bad_ssid', 'Name the network first'));
    }
    final token = await secrets.read(SecretKeys.pairingToken);
    if (token == null) return const Err(AuthFailure());
    api.token = token;
    final result = await api.postJson(
      ApiPaths.provision,
      body: <String, dynamic>{
        'wifi_ssid': ssid.trim(),
        'wifi_password': password,
        'app_token': token,
      },
    );
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(:final value) when value['ok'] == true => const Ok(null),
      Ok(:final value) => Err(
        DeviceFailure(
          _text(value['error']) ?? 'provision_failed',
          _text(value['message']) ?? 'Orion kept its network',
        ),
      ),
    };
  }

  String? _text(Object? value) => value is String ? value : null;
}

/// Always agrees, a moment later.
class FakeWifiChangeRepository implements WifiChangeRepository {
  @override
  Future<Result<void>> changeOverLan({
    required String ssid,
    required String password,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (ssid.trim().isEmpty) {
      return const Err(DeviceFailure('bad_ssid', 'Name the network first'));
    }
    return const Ok(null);
  }
}
