import 'dart:async';
import 'dart:typed_data';

import 'package:esp_ble_prov_dart/esp_ble_prov_dart.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:universal_ble/universal_ble.dart';

import '../../../../core/result.dart';
import '../../domain/nearby_board.dart';
import 'ble_contract.dart';
import 'ble_wire.dart';
import 'provisioning_link.dart';

/// The real radio. The only file that knows esp_ble_prov_dart and
/// universal_ble exist. Nothing here logs, because every payload after the
/// handshake carries a token or a password.
class EspProvisioningLink implements ProvisioningLink {
  EspBleProvisioner? _prov;

  @override
  bool get isSupported => true;

  @override
  bool get isOpen => _prov?.isConnected ?? false;

  @override
  Stream<NearbyBoard> scan() {
    StreamSubscription<BleDevice>? hits;
    late final StreamController<NearbyBoard> out;
    out = StreamController<NearbyBoard>(
      onListen: () async {
        try {
          await _radioReady();
          hits = UniversalBle.scanStream.listen((device) {
            final name = device.name ?? device.rawName ?? '';
            if (!name.startsWith(NearbyBoard.namePrefix)) return;
            out.add(
              NearbyBoard(id: device.deviceId, name: name, rssi: device.rssi),
            );
          });
          await _ble(
            () => UniversalBle.startScan(
              scanFilter: ScanFilter(withNamePrefix: [NearbyBoard.namePrefix]),
            ),
            BluetoothProblem.off,
          );
        } on BluetoothFailure catch (failure) {
          out.addError(failure);
          await out.close();
        }
      },
      onCancel: () async {
        await hits?.cancel();
        await _ble(
          UniversalBle.stopScan,
          BluetoothProblem.off,
        ).then((_) {}, onError: (Object _) {});
      },
    );
    return out.stream;
  }

  @override
  Future<void> open(NearbyBoard board, {required String pop}) async {
    final prov = EspBleProvisioner(
      deviceNamePrefix: NearbyBoard.namePrefix,
      security: Security1(pop: pop),
      // A wrong code makes the board drop the link mid handshake, and the
      // library waits this long before it gives up on the answer.
      responseTimeout: const Duration(seconds: 6),
    );
    await _ble(
      () => prov.connect(
        device: EspBleDevice(id: board.id, name: board.name),
        connectionTimeout: BleContract.connectTimeout,
      ),
      BluetoothProblem.lostBoard,
    );
    try {
      await _ble(prov.establishSession, BluetoothProblem.wrongCode);
    } on BluetoothFailure {
      await _ble(
        prov.disconnect,
        BluetoothProblem.lostBoard,
      ).then((_) {}, onError: (Object _) {});
      rethrow;
    }
    prov
      ..registerCustomEndpoint(
        BleContract.pairEndpoint,
        index: BleContract.pairEndpointIndex,
      )
      ..registerCustomEndpoint(
        BleContract.configEndpoint,
        index: BleContract.configEndpointIndex,
      );
    _prov = prov;
  }

  @override
  Future<List<BoardScanEntry>> scanNetworks() async {
    final prov = _open();
    final found = await _call(
      () => prov.scan(timeout: BleContract.wifiScanTimeout),
    );
    return [
      for (final n in found)
        BoardScanEntry(
          ssid: n.ssid,
          rssi: n.rssi,
          auth: n.auth.value,
          channel: n.channel,
        ),
    ];
  }

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List request) async {
    final prov = _open();
    return _call(() async {
      await prov.writeValueToEndpoint(endpoint, request);
      // The board answers inside the write, but give a slow one a moment.
      for (var attempt = 0; attempt < 5; attempt++) {
        final answer = await prov.readValueFromEndpoint(endpoint);
        if (answer.isNotEmpty) return answer;
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
      return Uint8List(0);
    });
  }

  @override
  Future<void> applyCredentials({
    required String ssid,
    required String password,
  }) async {
    final prov = _open();
    await _call(() async {
      await prov.setWiFiConfig(
        WiFiConfig(ssid: ssid, passphrase: password.isEmpty ? null : password),
      );
      await prov.applyWiFiConfig();
    });
  }

  @override
  Future<BoardWifiReport> wifiStatus() async {
    final prov = _open();
    final status = await _call(prov.getWiFiStatus);
    return BoardWifiReport(
      state: status.state.value,
      failReason: status.failReason?.value,
      ip: status.connected?.ip4Addr,
      attemptsRemaining: status.attemptsRemaining,
    );
  }

  @override
  Future<void> close() async {
    final prov = _prov;
    _prov = null;
    if (prov == null) return;
    await _ble(
      () => prov.disconnect(timeout: const Duration(seconds: 3)),
      BluetoothProblem.lostBoard,
    );
  }

  EspBleProvisioner _open() {
    final prov = _prov;
    if (prov == null || !prov.isConnected) {
      throw const BluetoothFailure(
        BluetoothProblem.lostBoard,
        'The Bluetooth link to Orion is closed',
      );
    }
    return prov;
  }

  /// A call on an open session. A failure after the link dropped is a lost
  /// board; one while it is still up is the board answering off script.
  Future<T> _call<T>(Future<T> Function() body) async {
    try {
      return await _ble(body, BluetoothProblem.protocol);
    } on BluetoothFailure catch (failure) {
      if (isOpen) rethrow;
      throw BluetoothFailure(BluetoothProblem.lostBoard, failure.message);
    }
  }

  Future<void> _radioReady() async {
    await _ble(UniversalBle.requestPermissions, BluetoothProblem.denied);
    var state = await _ble(
      UniversalBle.getBluetoothAvailabilityState,
      BluetoothProblem.unsupported,
    );
    // iOS reports unknown until CoreBluetooth has woken up.
    for (var i = 0; i < 15 && _settling(state); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      state = await _ble(
        UniversalBle.getBluetoothAvailabilityState,
        BluetoothProblem.unsupported,
      );
    }
    switch (state) {
      case AvailabilityState.poweredOn:
        return;
      case AvailabilityState.unauthorized:
        throw const BluetoothFailure(BluetoothProblem.denied, 'No permission');
      case AvailabilityState.unsupported:
        throw const BluetoothFailure(
          BluetoothProblem.unsupported,
          'This device has no Bluetooth LE',
        );
      case AvailabilityState.poweredOff:
      case AvailabilityState.unknown:
      case AvailabilityState.resetting:
        throw const BluetoothFailure(BluetoothProblem.off, 'Bluetooth is off');
    }
  }

  bool _settling(AvailabilityState s) =>
      s == AvailabilityState.unknown || s == AvailabilityState.resetting;

  /// Maps every exception the two packages throw onto one BluetoothFailure.
  Future<T> _ble<T>(Future<T> Function() body, BluetoothProblem problem) async {
    try {
      return await body();
    } on ProvisionerError catch (e) {
      throw BluetoothFailure(problem, e.message);
    } on UniversalBleException catch (e) {
      throw BluetoothFailure(problem, e.message);
    } on PlatformException catch (e) {
      throw BluetoothFailure(problem, e.message ?? e.code);
    } on TimeoutException {
      throw BluetoothFailure(problem, 'Orion did not answer over Bluetooth');
    }
  }
}
