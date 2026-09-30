import 'dart:typed_data';

import '../../domain/nearby_board.dart';
import 'ble_wire.dart';

/// The raw conversation with one board in setup mode: Espressif's protocomm
/// endpoints over an encrypted session. No app logic lives here, so the
/// repository above it can be tested against a fake board.
///
/// Every call throws a BluetoothFailure when it fails, never anything else.
abstract class ProvisioningLink {
  bool get isSupported;

  /// True while a session is open.
  bool get isOpen;

  /// Raw advertisement hits named Orion-*, repeats included, until cancelled.
  Stream<NearbyBoard> scan();

  /// Connects and runs the Security1 handshake with the code as the proof
  /// of possession. A code that does not match closes the link again.
  Future<void> open(NearbyBoard board, {required String pop});

  /// prov-scan: the board scans and reports every access point it heard.
  Future<List<BoardScanEntry>> scanNetworks();

  /// One encrypted request and response on a custom endpoint.
  Future<Uint8List> exchange(String endpoint, Uint8List request);

  /// prov-config: set, then apply.
  Future<void> applyCredentials({
    required String ssid,
    required String password,
  });

  /// prov-config: get status.
  Future<BoardWifiReport> wifiStatus();

  Future<void> close();
}
