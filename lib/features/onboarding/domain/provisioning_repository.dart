import '../../../core/result.dart';
import 'board_network.dart';
import 'join_status.dart';
import 'nearby_board.dart';

/// Setting up a board over Bluetooth, per DEVICE_PROTOCOL.md "Pairing over
/// Bluetooth". The calls go in this order: find, connect with the code,
/// scan, pair, send credentials, watch. After a failed join the session is
/// still open, so pair and send again without starting over.
abstract class ProvisioningRepository {
  /// False on a build or a device with no Bluetooth LE. The screens hide
  /// the Bluetooth path and keep the address entry.
  bool get isSupported;

  /// Boards in setup mode nearby, strongest first, growing while listened
  /// to. Errors are [BluetoothFailure]s: off, denied, unsupported.
  Stream<List<NearbyBoard>> findBoards();

  /// Opens the link and proves the code shown on the board's screen.
  Future<Result<void>> connect(NearbyBoard board, {required String code});

  /// What the board can see, strongest first, one entry per name, hidden
  /// networks left out.
  Future<Result<List<BoardNetwork>>> scanNetworks();

  /// Hands the board the app token and a name, over orion-pair. Keeps the
  /// token already on file so a board paired before stays paired. Returns
  /// the board's device id.
  Future<Result<String>> pair({required String deviceName});

  /// Sends the network and applies it. Progress comes from [watchStatus].
  Future<Result<void>> sendCredentials({
    required String ssid,
    required String password,
  });

  /// True while the encrypted session is open and orion-pair went through,
  /// the only time orion-config is accepted.
  bool get canSendConfig;

  /// A partial config, as a POST /api/config body, over orion-config.
  /// Returns the merged config, masked, as GET /api/config would.
  Future<Result<Map<String, dynamic>>> sendConfig(Map<String, dynamic> patch);

  /// The board's report until it lands on connected or failed.
  Stream<JoinStatus> watchStatus();

  /// Drops the link. Safe to call twice.
  Future<void> disconnect();
}
