import 'dart:math';

import '../../../core/network/api_paths.dart';
import '../../../core/network/device_api.dart';
import '../../../core/result.dart';
import '../../../core/storage/secret_store.dart';
import '../../device/domain/device.dart';
import '../domain/device_discovery.dart';
import '../domain/pairing_repository.dart';
import 'app_token.dart';

/// Hands the board Wi-Fi and a fresh token, then waits for it to come back
/// on the home network.
class HttpPairingRepository implements PairingRepository {
  HttpPairingRepository({
    required this.secrets,
    required this.discovery,
    this.waitForBoard = const Duration(seconds: 30),
    Random? random,
  }) : _random = random ?? Random.secure();

  final SecretStore secrets;
  final DeviceDiscovery discovery;
  final Random _random;

  /// How long to keep looking for the board after it reboots onto Wi-Fi.
  final Duration waitForBoard;

  /// The token a code pairing will store, made when the code is asked for.
  String? _pending;

  @override
  Future<Result<bool>> requestCode({required String host}) async {
    final token = _pending ??= newAppToken(_random);
    final api = DeviceApi(host: host);
    try {
      final result = await api.postJson(
        ApiPaths.pair,
        body: <String, dynamic>{'app_token': token},
      );
      return switch (result) {
        Ok(:final value) => Ok(
          value['error'] == 'code_required' || value['ok'] == true,
        ),
        // A board from before code pairing, or the mock's access point path.
        Err(failure: NotFoundFailure()) => const Ok(false),
        Err(:final failure) => Err(failure),
      };
    } finally {
      await api.close();
    }
  }

  @override
  Future<Result<Device>> pairWithCode({
    required String host,
    required String code,
  }) async {
    final token = _pending ??= newAppToken(_random);
    final api = DeviceApi(host: host);
    final Result<Map<String, dynamic>> result;
    try {
      result = await api.postJson(
        ApiPaths.pair,
        body: <String, dynamic>{'app_token': token, 'code': code.trim()},
      );
    } finally {
      await api.close();
    }
    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (value['ok'] != true) {
          return const Err(
            DeviceFailure('pair_failed', 'Orion did not take that code'),
          );
        }
        // Stored before the first request that uses it.
        await secrets.write(SecretKeys.pairingToken, token);
        _pending = null;
        final id = value['device_id'] as String? ?? 'orion';
        final device = (await discovery.probe(host)).valueOrNull;
        return Ok(device ?? Device(id: id, name: 'Orion', host: host));
    }
  }

  @override
  Future<Result<Device>> pair({
    required String host,
    required String wifiSsid,
    required String wifiPassword,
    required String deviceName,
  }) async {
    final token = newAppToken(_random);
    final api = DeviceApi(host: host);
    final Result<Map<String, dynamic>> result;
    try {
      result = await api.postJson(
        ApiPaths.provision,
        body: <String, dynamic>{
          'wifi_ssid': wifiSsid,
          'wifi_password': wifiPassword,
          'app_token': token,
          'device_name': deviceName,
        },
      );
    } finally {
      await api.close();
    }

    switch (result) {
      case Err(:final failure):
        return Err(failure);
      case Ok(:final value):
        if (value['ok'] != true) {
          return const Err(DeviceFailure('provision_failed', 'Orion said no'));
        }
        final id = value['device_id'] as String? ?? 'orion';
        // The token has to be stored before the first request that uses it.
        await secrets.write(SecretKeys.pairingToken, token);
        final settled = await _findAgain(id, host);
        return Ok(settled ?? Device(id: id, name: deviceName, host: host));
    }
  }

  /// The board reboots onto the home Wi-Fi and usually lands on a new
  /// address, so look for it again before giving up on the old one.
  Future<Device?> _findAgain(String id, String host) async {
    final deadline = DateTime.now().add(waitForBoard);
    while (DateTime.now().isBefore(deadline)) {
      for (final candidate in <String>[host, 'orion.local']) {
        final device = (await discovery.probe(candidate)).valueOrNull;
        if (device != null && device.id == id) return device;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    return null;
  }
}
