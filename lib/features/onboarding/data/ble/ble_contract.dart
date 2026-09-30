/// The Bluetooth half of DEVICE_PROTOCOL.md in one place. When the firmware
/// names a different endpoint or UUID, this is the only file that moves.
abstract final class BleContract {
  /// The custom protocomm endpoint that takes the app token.
  static const pairEndpoint = 'orion-pair';

  /// ESP-IDF numbers custom endpoints from 0xff54 in the order the firmware
  /// creates them. orion-pair is the first and only one.
  static const pairEndpointIndex = 0;

  /// The config, written after orion-pair, so keys never cross the LAN in
  /// the clear during onboarding. The second custom endpoint, 0xff55.
  static const configEndpoint = 'orion-config';
  static const configEndpointIndex = 1;

  /// Above this many bytes of JSON the config goes in parts. A GATT value
  /// tops out at 512 bytes and the session adds nothing, so this leaves
  /// room for the part wrapper and JSON escaping.
  static const configWholeMax = 400;
  static const configSliceChars = 150;

  /// The code on the board's screen is always six digits.
  static const codeLength = 6;

  /// How long to wait for the Bluetooth link itself.
  static const connectTimeout = Duration(seconds: 15);

  /// A board scan covers every 2.4 GHz channel; a busy block takes a while.
  static const wifiScanTimeout = Duration(seconds: 30);

  /// Polling cadence and patience while the board joins the network.
  static const statusEvery = Duration(seconds: 1);
  static const joinTimeout = Duration(seconds: 45);
}
