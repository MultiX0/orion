import '../../../core/result.dart';
import '../../device/domain/device.dart';

/// Finds boards on the LAN. Manual entry goes through probe.
abstract class DeviceDiscovery {
  /// Emits the growing list of boards seen so far while listened to.
  Stream<List<Device>> discover();

  /// Asks one host for /api/info. host is an ip or host:port.
  Future<Result<Device>> probe(String host);
}
