import 'dart:async';

import '../../../core/network/device_probe.dart';
import '../../../core/network/lan_discovery.dart';
import '../../../core/result.dart';
import '../../device/domain/device.dart';
import '../domain/device_discovery.dart';

/// Beacon, mDNS, a sweep of the local /24s and the .local names, merged and
/// confirmed by /api/info. Manual entry goes through a patient probe, since
/// a person typing an address deserves more than 400 ms.
class LanDeviceDiscovery implements DeviceDiscovery {
  LanDeviceDiscovery({
    DeviceProbe? fastProbe,
    DeviceProbe? patientProbe,
    LanDiscovery Function(ConfirmHost confirm)? buildDiscovery,
    String? knownDeviceId,
  }) : _fast = fastProbe ?? DeviceProbe(),
       _patient =
           patientProbe ?? DeviceProbe(timeout: const Duration(seconds: 4)) {
    _discovery =
        buildDiscovery?.call(_confirm) ??
        LanDiscovery(
          confirm: _confirm,
          nameHints: LanDiscovery.nameHintsFor(knownDeviceId),
        );
  }

  final DeviceProbe _fast;
  final DeviceProbe _patient;
  late final LanDiscovery _discovery;

  Future<Result<Device>> _confirm(String host, {String source = 'manual'}) =>
      _fast.probe(host, source: source);

  @override
  Stream<List<Device>> discover() async* {
    final found = <Device>[];
    await for (final device in _discovery.devices()) {
      found.add(device);
      yield List.unmodifiable(found);
    }
  }

  @override
  Future<Result<Device>> probe(String host) =>
      _patient.probe(host, source: DiscoverySource.manual);
}
