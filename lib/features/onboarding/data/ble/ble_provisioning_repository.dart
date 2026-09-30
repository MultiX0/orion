import 'dart:async';
import 'dart:math';

import '../../../../core/result.dart';
import '../../../../core/storage/secret_store.dart';
import '../../domain/board_network.dart';
import '../../domain/join_status.dart';
import '../../domain/nearby_board.dart';
import '../../domain/provisioning_repository.dart';
import '../app_token.dart';
import 'ble_contract.dart';
import 'ble_mappers.dart';
import 'ble_wire.dart';
import 'config_parts.dart';
import 'provisioning_link.dart';

/// The Bluetooth setup, over whichever link it is given: the real radio on
/// a phone, the scripted board in tests and on a desktop.
class BleProvisioningRepository implements ProvisioningRepository {
  BleProvisioningRepository({
    required this.link,
    required this.secrets,
    this.statusEvery = BleContract.statusEvery,
    this.joinTimeout = BleContract.joinTimeout,
    this.random,
  });

  final ProvisioningLink link;
  final SecretStore secrets;
  final Duration statusEvery;
  final Duration joinTimeout;
  final Random? random;
  NearbyBoard? _board;
  bool _paired = false;

  static const _unsupported = BluetoothFailure(
    BluetoothProblem.unsupported,
    'Bluetooth setup needs a phone',
  );

  @override
  bool get isSupported => link.isSupported;

  @override
  Stream<List<NearbyBoard>> findBoards() async* {
    if (!isSupported) throw _unsupported;
    final seen = <String, NearbyBoard>{};
    await for (final hit in link.scan()) {
      final before = seen[hit.id];
      // Keep the last known signal when an advertisement comes without one.
      seen[hit.id] = hit.rssi == null && before != null
          ? hit.copyWith(rssi: before.rssi)
          : hit;
      yield _strongestFirst(seen.values);
    }
  }

  @override
  Future<Result<void>> connect(NearbyBoard board, {required String code}) {
    final digits = code.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(digits)) {
      return Future.value(
        const Err(
          BluetoothFailure(
            BluetoothProblem.wrongCode,
            'The code is the six digits on the board',
          ),
        ),
      );
    }
    return _guard(() async {
      if (link.isOpen) await link.close();
      await link.open(board, pop: digits);
      _board = board;
      _paired = false;
    });
  }

  @override
  Future<Result<List<BoardNetwork>>> scanNetworks() =>
      _guard(() async => tidyNetworks(await link.scanNetworks()));

  @override
  Future<Result<String>> pair({required String deviceName}) async {
    final token =
        await secrets.read(SecretKeys.pairingToken) ?? newAppToken(random);
    final name = deviceName.trim().isEmpty ? 'Orion' : deviceName.trim();
    final request = OrionPairRequest(appToken: token, deviceName: name);
    final sent = await _guard(
      () => link.exchange(BleContract.pairEndpoint, encodePairRequest(request)),
    );
    final Result<OrionPairResponse> parsed = switch (sent) {
      Ok(:final value) => parsePairResponse(value),
      Err(:final failure) => Err(failure),
    };
    switch (parsed) {
      case Err(:final failure):
        return Err(failure);
      case Ok(
        value: OrionPairResponse(ok: false, :final error, :final message),
      ):
        return Err(
          DeviceFailure(error ?? 'pair_refused', message ?? 'Orion said no'),
        );
      case Ok(:final value):
        // Stored before the credentials go out, so the first LAN request
        // after the board lands already carries it.
        await secrets.write(SecretKeys.pairingToken, token);
        _paired = true;
        // The id ends in the same four characters the board advertises.
        return Ok(value.deviceId ?? 'orion-${_board?.suffix ?? 'board'}');
    }
  }

  @override
  bool get canSendConfig => isSupported && link.isOpen && _paired;

  @override
  Future<Result<Map<String, dynamic>>> sendConfig(
    Map<String, dynamic> patch,
  ) async {
    if (!canSendConfig) {
      return const Err(
        BluetoothFailure(
          BluetoothProblem.lostBoard,
          'The Bluetooth setup session is closed',
        ),
      );
    }
    final writes = configWrites(patch);
    for (var i = 0; i < writes.length; i++) {
      final sent = await _guard(
        () => link.exchange(BleContract.configEndpoint, writes[i]),
      );
      if (sent case Err(:final failure)) return Err(failure);
      final answer = sent.valueOrNull!;
      final last = i == writes.length - 1;
      if (last) return parseConfigAnswer(answer);
      final ack = parsePartAck(answer, i + 1);
      if (ack case Err(:final failure)) return Err(failure);
    }
    return const Err(ParseFailure('Nothing to send'));
  }

  @override
  Future<Result<void>> sendCredentials({
    required String ssid,
    required String password,
  }) {
    if (ssid.trim().isEmpty) {
      return Future.value(
        const Err(DeviceFailure('bad_ssid', 'Name the network first')),
      );
    }
    return _guard(
      () => link.applyCredentials(ssid: ssid.trim(), password: password),
    );
  }

  @override
  Stream<JoinStatus> watchStatus() async* {
    yield const JoinStatus.connecting();
    final deadline = DateTime.now().add(joinTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(statusEvery);
      final report = await _guard(link.wifiStatus);
      switch (report) {
        case Err():
          yield const JoinStatus.failed(JoinFailure.lostBoard);
          return;
        case Ok(:final value):
          final status = joinStatusFrom(value);
          if (status is JoinConnecting) continue;
          yield status;
          return;
      }
    }
    yield const JoinStatus.failed(JoinFailure.timedOut);
  }

  @override
  Future<void> disconnect() async {
    _paired = false;
    await _guard(link.close);
  }

  List<NearbyBoard> _strongestFirst(Iterable<NearbyBoard> boards) =>
      boards.toList()
        ..sort((a, b) => (b.rssi ?? -127).compareTo(a.rssi ?? -127));

  /// The link throws BluetoothFailure and nothing else; this turns it into
  /// a Result so the screens never see an exception.
  Future<Result<T>> _guard<T>(Future<T> Function() call) async {
    if (!isSupported) return const Err(_unsupported);
    try {
      return Ok(await call());
    } on BluetoothFailure catch (failure) {
      return Err(failure);
    }
  }
}
