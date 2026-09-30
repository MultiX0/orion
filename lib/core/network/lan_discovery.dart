import 'dart:async';

import '../../features/device/domain/device.dart';
import '../result.dart';
import 'beacon_listener.dart';
import 'mdns_scanner.dart';
import 'net_interfaces.dart';
import 'task_pool.dart';

/// How a board turned up. The UI shows this as a mono tag.
abstract final class DiscoverySource {
  static const beacon = 'beacon';
  static const mdns = 'mdns';
  static const sweep = 'sweep';
  static const name = 'name';
  static const manual = 'manual';
}

/// Asks one host for /api/info and returns the board, or a failure.
typedef ConfirmHost =
    Future<Result<Device>> Function(String host, {String source});

/// Four ways of finding a board, one deduped stream. Every hit is confirmed
/// by a real /api/info call before it reaches the UI, so a board only ever
/// appears once and only when it is actually answering.
class LanDiscovery {
  LanDiscovery({
    required this.confirm,
    MdnsScanner? mdns,
    BeaconListener? beacon,
    List<String>? nameHints,
    this.sweepAddresses,
    this.concurrency = 64,
    this.sweepInterfaces = 3,
  }) : _mdns = mdns ?? MdnsScanner(),
       _beacon = beacon ?? BeaconListener(),
       _nameHints = nameHints ?? nameHintsFor(null);

  final ConfirmHost confirm;
  final MdnsScanner _mdns;
  final BeaconListener _beacon;
  final List<String> _nameHints;

  /// Injected in tests. Null means "ask the OS for this machine's addresses".
  final List<String>? sweepAddresses;

  final int concurrency;
  final int sweepInterfaces;

  /// The names an Orion board answers to. The last four of a known device id
  /// give the second one, so a second board on the LAN is still reachable.
  static List<String> nameHintsFor(String? deviceId, {int mockPort = 8080}) {
    final hints = <String>['orion.local', 'localhost:$mockPort'];
    if (deviceId != null && deviceId.length >= 4) {
      final last4 = deviceId.substring(deviceId.length - 4);
      hints.insert(1, 'orion-$last4.local');
    }
    return hints;
  }

  /// Boards as they are confirmed, each one only once. The stream stays open
  /// while the beacon listener does, which on a real LAN is until the screen
  /// closes it: a board that boots late still turns up.
  Stream<Device> devices() {
    final pool = TaskPool(concurrency);
    final seen = <String>{};
    final subs = <StreamSubscription<void>>[];
    final inFlight = <Future<void>>[];
    var stopped = false;
    late final StreamController<Device> out;

    Future<void> consider(String host, String source) async {
      if (stopped || out.isClosed) return;
      final result = await pool.run(() => confirm(host, source: source));
      if (stopped || out.isClosed) return;
      final device = result.valueOrNull;
      if (device == null || !seen.add(device.id)) return;
      out.add(device);
    }

    void track(String host, String source) =>
        inFlight.add(consider(host, source));

    out = StreamController<Device>(
      onListen: () {
        final beaconDone = Completer<void>();
        final mdnsDone = Completer<void>();
        subs.add(
          _beacon.listen().listen(
            (packet) => track(packet.host, DiscoverySource.beacon),
            onError: (Object _) {},
            onDone: beaconDone.complete,
          ),
        );
        subs.add(
          _mdns.scan().listen(
            (service) => track(service.hostWithPort, DiscoverySource.mdns),
            onError: (Object _) {},
            onDone: mdnsDone.complete,
          ),
        );
        for (final name in _nameHints) {
          track(name, DiscoverySource.name);
        }
        final scans = <Future<void>>[
          beaconDone.future,
          mdnsDone.future,
          _sweep(track, () => stopped),
        ];
        unawaited(_closeWhenIdle(out, scans, inFlight, () => stopped));
      },
      onCancel: () async {
        stopped = true;
        for (final sub in subs) {
          await sub.cancel();
        }
        if (!out.isClosed) await out.close();
      },
    );
    return out.stream;
  }

  /// Every source has finished and every probe has answered, so there is
  /// nothing left that could ever add a board.
  Future<void> _closeWhenIdle(
    StreamController<Device> out,
    List<Future<void>> scans,
    List<Future<void>> inFlight,
    bool Function() stopped,
  ) async {
    await Future.wait(scans);
    while (inFlight.isNotEmpty && !stopped()) {
      final batch = List<Future<void>>.of(inFlight);
      inFlight.clear();
      await Future.wait(batch);
    }
    if (!out.isClosed) await out.close();
  }

  Future<void> _sweep(
    void Function(String host, String source) consider,
    bool Function() stopped,
  ) async {
    final addresses =
        sweepAddresses ??
        await NetInterfaces.sweepAddresses(max: sweepInterfaces);
    for (final address in addresses) {
      if (stopped()) return;
      for (final host in NetInterfaces.hostsFor(address)) {
        consider(host, DiscoverySource.sweep);
      }
    }
  }
}
