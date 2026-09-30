import 'package:freezed_annotation/freezed_annotation.dart';

part 'board_network.freezed.dart';

/// A Wi-Fi network as the board sees it. The board scans, not the phone,
/// so this is what it can actually reach, 2.4 GHz only.
@freezed
abstract class BoardNetwork with _$BoardNetwork {
  const BoardNetwork._();

  const factory BoardNetwork({
    required String ssid,

    /// Signal strength in dBm, closer to zero is stronger.
    required int rssi,

    /// True when the network asks for a password.
    required bool secured,
  }) = _BoardNetwork;

  /// Zero to three bars, the way a phone's status bar would draw it.
  int get bars => barsFor(rssi);

  /// The same scale for anything with a signal, a nearby board included.
  static int barsFor(int? rssi) {
    if (rssi == null) return 0;
    if (rssi >= -60) return 3;
    if (rssi >= -70) return 2;
    if (rssi >= -80) return 1;
    return 0;
  }
}
