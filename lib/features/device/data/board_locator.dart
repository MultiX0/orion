import 'dart:async';
import 'dart:math' show min;

import 'package:flutter/foundation.dart' show debugPrint;

import '../../../core/network/device_probe.dart';
import '../../../core/network/lan_discovery.dart';
import '../../../core/network/net_interfaces.dart';
import '../domain/connection_status.dart';
import '../domain/device.dart';

/// Orion Link on the app side (docs/ORION_LINK.md): the paired board is
/// known by its id, and its address is only where it was last seen. When the
/// board stops answering there (DHCP gave it another one), this looks for the
/// same id on the network and moves the pairing to where it is now. The
/// connection follows, since it is built from the paired device.
class BoardLocator {
  BoardLocator({
    required this.find,
    required this.moved,
    this.after = const Duration(seconds: 8),
    this.every = const Duration(seconds: 45),
    void Function(String line)? log,
  }) : _log = log ?? debugPrint;

  /// The board with this id, wherever it answers now, or null.
  final Future<Device?> Function(Device paired) find;

  /// Saves the pairing at its new address.
  final Future<void> Function(Device now) moved;

  /// How long the board may be away before anyone looks for it: a reconnect
  /// after a blip should not cost a sweep of the network.
  final Duration after;

  /// The wait after the first look. It doubles after every look while the
  /// board stays away, up to 16 times this (12 min): an unplugged board, or
  /// a phone on another network, is not searched for every minute for hours.
  final Duration every;

  /// Every move is written down: the pairing, and its token, now go to
  /// another address.
  final void Function(String line) _log;

  Device? _paired;
  var _connected = false;
  var _busy = false;
  Timer? _timer;
  var _disposed = false;

  /// Looks since the socket was last up or the pairing last changed.
  var _misses = 0;

  /// Called on every change of the pairing or of the connection.
  void update(Device? paired, ConnectionStatus status) {
    final changed = paired?.id != _paired?.id || paired?.host != _paired?.host;
    _paired = paired;
    _connected = status == ConnectionStatus.connected;
    // A live socket or another pairing starts the waits over. Other status
    // changes do not: the reconnect loop toggles them all the time.
    if (_connected || changed) {
      _misses = 0;
      _timer?.cancel();
      _timer = null;
    }
    // A look in progress schedules the next one itself.
    if (_connected || paired == null || _busy) return;
    _timer ??= Timer(after, _look);
  }

  Future<void> _look() async {
    _timer = null;
    final paired = _paired;
    if (_disposed || paired == null || _connected || _busy) return;
    _busy = true;
    try {
      final found = await find(paired);
      // Still the same pairing, still away, and really somewhere else.
      if (!_disposed &&
          found != null &&
          found.id == paired.id &&
          _paired?.id == paired.id &&
          _paired?.host == paired.host &&
          found.host != paired.host &&
          !_connected) {
        _log(
          'Orion Link: board ${paired.id} no longer answers at '
          '${paired.host}; the pairing moves to ${found.host} '
          '(found by ${found.source ?? 'unknown'})',
        );
        await moved(paired.copyWith(host: found.host, source: found.source));
      }
    } on Object {
      // A failed look is the same as not finding it: try again later.
    } finally {
      _busy = false;
    }
    if (!_disposed && !_connected && _paired != null && _timer == null) {
      _timer = Timer(every * (1 << min(_misses, 4)), _look);
      _misses++;
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}

/// The paired board, wherever it answers now, or null.
///
/// The last address is asked first, and again before a hit anywhere else is
/// handed back: a board that still answers there as itself is never moved,
/// whatever else keeps its socket down. Only then does every discovery
/// source run at once (beacon, mDNS, the .local names and a sweep of the
/// board's last /24), for up to [limit]. Each hit is confirmed by the
/// board's own /api/info, so a stale beacon cannot move the pairing.
/// [confirm] and [build] keep tests off the network.
Future<Device?> findBoardById(
  Device paired, {
  ConfirmHost? confirm,
  LanDiscovery Function(ConfirmHost confirm)? build,
  Duration limit = const Duration(seconds: 25),
}) async {
  // Patient at the last address: a slow answer there must not read as gone.
  final patient = DeviceProbe(timeout: const Duration(seconds: 2));
  final fast = DeviceProbe();
  final atLast = confirm ?? patient.probe;
  final check = confirm ?? fast.probe;
  Future<bool> stillThere() async =>
      (await atLast(paired.host)).valueOrNull?.id == paired.id;
  try {
    if (await stillThere()) return paired;
    final discovery =
        build?.call(check) ??
        LanDiscovery(
          confirm: check,
          nameHints: LanDiscovery.nameHintsFor(paired.id),
          sweepAddresses: NetInterfaces.onSameSubnet(
            paired.host,
            await NetInterfaces.list(),
          ),
        );
    final hit = await _firstWithId(discovery, paired.id, limit);
    if (hit == null || hit.host == paired.host) return hit;
    return await stillThere() ? paired : hit;
  } finally {
    patient.close();
    fast.close();
  }
}

Future<Device?> _firstWithId(
  LanDiscovery discovery,
  String id,
  Duration limit,
) async {
  final done = Completer<Device?>();
  late final StreamSubscription<Device> sub;
  sub = discovery.devices().listen(
    (d) {
      if (d.id == id && !done.isCompleted) done.complete(d);
    },
    onError: (Object _) {},
    onDone: () {
      if (!done.isCompleted) done.complete(null);
    },
  );
  final timer = Timer(limit, () {
    if (!done.isCompleted) done.complete(null);
  });
  try {
    return await done.future;
  } finally {
    timer.cancel();
    // Stops the beacon listener and the sweep, which would otherwise run on.
    await sub.cancel();
  }
}
