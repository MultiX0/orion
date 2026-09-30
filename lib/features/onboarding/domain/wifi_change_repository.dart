import '../../../core/result.dart';

/// Moves the paired board to another network while it is online, over the
/// LAN with its token. When it is out of reach the Bluetooth setup does it.
abstract class WifiChangeRepository {
  Future<Result<void>> changeOverLan({
    required String ssid,
    required String password,
  });
}
