import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Broadcasts the board beacon from docs/DEVICE_PROTOCOL.md every two
/// seconds, once per local IPv4 address, so a phone on the LAN finds the
/// mock the same way it would find a real board.
class MockBeacon {
  MockBeacon({
    required this.deviceId,
    required this.name,
    required this.httpPort,
    this.fwVersion = '0.1.0-mock',
    this.port = 7332,
    this.broadcastAddress = '255.255.255.255',
  });

  final String deviceId;
  final String name;
  final int httpPort;
  final String fwVersion;
  final int port;

  /// Loopback in tests, the broadcast address everywhere else.
  final String broadcastAddress;

  RawDatagramSocket? _socket;
  Timer? _timer;

  /// Returns false when the socket will not bind, which is not fatal: the
  /// app still finds the mock through mDNS, the sweep or localhost.
  Future<bool> start() async {
    try {
      _socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
    } on SocketException {
      return false;
    }
    _socket!.broadcastEnabled = true;
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _send());
    await _send();
    return true;
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _socket?.close();
    _socket = null;
  }

  Future<void> _send() async {
    final socket = _socket;
    if (socket == null) return;
    for (final ip in await _localIps()) {
      final payload = utf8.encode(
        jsonEncode(<String, dynamic>{
          'orion': 1,
          'device_id': deviceId,
          'name': name,
          'fw': fwVersion,
          'ip': ip,
          'port': httpPort,
        }),
      );
      try {
        socket.send(payload, InternetAddress(broadcastAddress), port);
      } on SocketException {
        return; // No route right now. The next tick tries again.
      }
    }
  }

  Future<List<String>> _localIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      final ips = <String>[
        for (final nic in interfaces)
          for (final addr in nic.addresses)
            if (!addr.isLinkLocal) addr.address,
      ];
      return ips.isEmpty ? <String>['127.0.0.1'] : ips;
    } on SocketException {
      return <String>['127.0.0.1'];
    }
  }
}
