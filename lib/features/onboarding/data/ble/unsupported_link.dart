import 'dart:typed_data';

import '../../../../core/result.dart';
import '../../domain/nearby_board.dart';
import 'ble_wire.dart';
import 'provisioning_link.dart';

/// For builds with no Bluetooth path. The screens check isSupported first
/// and never reach the calls.
class UnsupportedLink implements ProvisioningLink {
  static const _no = BluetoothFailure(
    BluetoothProblem.unsupported,
    'Bluetooth setup needs a phone',
  );

  @override
  bool get isSupported => false;

  @override
  bool get isOpen => false;

  @override
  Stream<NearbyBoard> scan() => Stream.error(_no);

  @override
  Future<void> open(NearbyBoard board, {required String pop}) => throw _no;

  @override
  Future<List<BoardScanEntry>> scanNetworks() => throw _no;

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List request) => throw _no;

  @override
  Future<void> applyCredentials({
    required String ssid,
    required String password,
  }) => throw _no;

  @override
  Future<BoardWifiReport> wifiStatus() => throw _no;

  @override
  Future<void> close() async {}
}
