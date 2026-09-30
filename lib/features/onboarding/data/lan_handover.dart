import '../../device/domain/device.dart';
import '../domain/device_discovery.dart';

/// After the board says "connected" over Bluetooth, find it on the LAN the
/// same way the rest of the app does, through /api/info.
class LanHandover {
  LanHandover({
    required this.discovery,
    this.patience = const Duration(seconds: 30),
    this.every = const Duration(seconds: 2),
  });

  final DeviceDiscovery discovery;
  final Duration patience;
  final Duration every;

  /// The board as the LAN sees it. If it never answers, for example because
  /// the phone sits on a guest network, the address the board reported is
  /// still the best guess, so it comes back with that and found false.
  Future<({Device device, bool found})> find({
    required String deviceId,
    required String ip,
    required String name,
  }) async {
    final named = 'orion-${_last4(deviceId)}.local';
    final deadline = DateTime.now().add(patience);
    while (true) {
      // The address came from the board itself, so whoever answers there is
      // the board. The .local name has to prove it with the id.
      final direct = (await discovery.probe(ip)).valueOrNull;
      if (direct != null) return (device: direct, found: true);
      final byName = (await discovery.probe(named)).valueOrNull;
      if (byName != null && byName.id == deviceId) {
        return (device: byName, found: true);
      }
      if (!DateTime.now().add(every).isBefore(deadline)) break;
      await Future<void>.delayed(every);
    }
    return (
      device: Device(id: deviceId, name: name, host: ip, source: 'bluetooth'),
      found: false,
    );
  }

  String _last4(String id) => id.length <= 4 ? id : id.substring(id.length - 4);
}
