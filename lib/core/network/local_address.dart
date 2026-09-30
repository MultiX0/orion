import 'dart:io';

import 'net_interfaces.dart';

/// Runs a command and hands back its stdout. Swapped in tests.
typedef RunCommand = Future<String> Function(String exe, List<String> args);

/// Which of this machine's addresses the board should knock on. Asking the
/// OS for "an IPv4" is not enough: on a PC with Hyper-V or WSL the first
/// answer is a virtual adapter the board cannot reach.
abstract final class LocalAddress {
  /// Opens a TCP connection to the board and reads the local end of it.
  /// That address is reachable from the board by construction.
  static Future<String?> towards(
    String host, {
    int port = 80,
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final target = _hostOnly(host);
    final targetPort = _portOf(host) ?? port;
    Socket? socket;
    try {
      socket = await Socket.connect(target, targetPort, timeout: timeout);
      final local = socket.address.address;
      if (local != socket.remoteAddress.address) return local;
      // On Windows socket.address can come back as the board's own address,
      // which would tell the board to call itself. The board is reachable,
      // so this PC has an adapter on its subnet: use that one.
      // Loopback is the one case where both ends really are the same.
      return await sameSubnet(target) ?? local;
    } on SocketException {
      return null;
    } on ArgumentError {
      return null;
    } finally {
      socket?.destroy();
    }
  }

  /// This machine's IPv4 address that shares the most leading octets with
  /// [target], at least two: 172.16.0.119 for a board at 172.16.0.136, not
  /// the WSL adapter at 172.30.48.1.
  static Future<String?> sameSubnet(
    String target, {
    Future<List<String>> Function()? addresses,
  }) async {
    final mine = await (addresses ?? _ownAddresses)();
    final want = target.split('.');
    String? best;
    var bestShared = 1;
    for (final a in mine) {
      final parts = a.split('.');
      var shared = 0;
      while (shared < 4 &&
          shared < parts.length &&
          parts[shared] == want[shared]) {
        shared++;
      }
      if (shared > bestShared && a != target) {
        best = a;
        bestShared = shared;
      }
    }
    return best;
  }

  static Future<List<String>> _ownAddresses() async {
    final nics = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final n in nics)
        for (final a in n.addresses) a.address,
    ];
  }

  /// The address of the interface that owns the default route. Used when the
  /// board is asleep or has never been seen.
  static Future<String?> defaultRoute({RunCommand? run}) async {
    final exec = run ?? _run;
    if (Platform.isWindows) {
      return parseRoutePrint(await exec('route', <String>['print', '-4']));
    }
    if (Platform.isLinux || Platform.isMacOS) {
      return parseIpRoute(await exec('ip', <String>['route']));
    }
    return null;
  }

  /// The interface column of the 0.0.0.0 route with the lowest metric.
  static String? parseRoutePrint(String output) {
    ({String address, int metric})? best;
    for (final raw in output.split('\n')) {
      final parts = raw.trim().split(RegExp(r'\s+'));
      if (parts.length < 5 || parts[0] != '0.0.0.0' || parts[1] != '0.0.0.0') {
        continue;
      }
      final address = parts[3];
      final metric = int.tryParse(parts[4]) ?? 9999;
      if (!_isIpv4(address) || address == '0.0.0.0') continue;
      if (best == null || metric < best.metric) {
        best = (address: address, metric: metric);
      }
    }
    return best?.address;
  }

  /// `default via 192.168.1.1 dev wlan0 proto dhcp src 192.168.1.20`.
  static String? parseIpRoute(String output) {
    for (final raw in output.split('\n')) {
      final line = raw.trim();
      if (!line.startsWith('default')) continue;
      final parts = line.split(RegExp(r'\s+'));
      final at = parts.indexOf('src');
      if (at >= 0 && at + 1 < parts.length && _isIpv4(parts[at + 1])) {
        return parts[at + 1];
      }
    }
    return null;
  }

  /// The board first, the default route second, any real adapter last.
  static Future<String?> best({String? boardHost, RunCommand? run}) async {
    if (boardHost != null && boardHost.isNotEmpty) {
      final reachable = await towards(boardHost);
      if (reachable != null) return reachable;
    }
    final routed = await defaultRoute(run: run);
    if (routed != null) return routed;
    final nics = NetInterfaces.order(await NetInterfaces.list());
    return nics.isEmpty ? null : nics.first.address;
  }

  /// What goes into pc.base_url.
  static Future<String?> baseUrlFor({
    required int port,
    String? boardHost,
    RunCommand? run,
  }) async {
    final address = await best(boardHost: boardHost, run: run);
    return address == null ? null : 'http://$address:$port';
  }

  static Future<String> _run(String exe, List<String> args) async {
    try {
      final result = await Process.run(
        exe,
        args,
      ).timeout(const Duration(seconds: 5));
      return '${result.stdout}';
    } on Object {
      return '';
    }
  }

  static String _hostOnly(String host) {
    final at = host.lastIndexOf(':');
    return at > 0 ? host.substring(0, at) : host;
  }

  static int? _portOf(String host) {
    final at = host.lastIndexOf(':');
    return at > 0 ? int.tryParse(host.substring(at + 1)) : null;
  }

  static bool _isIpv4(String value) {
    final parts = value.split('.');
    if (parts.length != 4) return false;
    return parts.every((p) {
      final n = int.tryParse(p);
      return n != null && n >= 0 && n <= 255;
    });
  }
}
