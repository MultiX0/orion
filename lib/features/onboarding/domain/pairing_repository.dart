import '../../../core/result.dart';
import '../../device/domain/device.dart';

/// Two ways in. A board already on the network pairs with the six digits it
/// shows on its own screen, which is how a reinstalled app or a second device
/// gets in without touching Wi-Fi. The access point path hands a board on its
/// setup network Wi-Fi and a fresh app token, then waits for it to come back.
abstract class PairingRepository {
  /// Asks the board to show a code. Ok(true) when it did; Ok(false) when it
  /// has no code pairing and the access point path is the way in.
  Future<Result<bool>> requestCode({required String host});

  /// The code from the board's screen. Stores the token on success.
  Future<Result<Device>> pairWithCode({
    required String host,
    required String code,
  });

  Future<Result<Device>> pair({
    required String host,
    required String wifiSsid,
    required String wifiPassword,
    required String deviceName,
  });
}
