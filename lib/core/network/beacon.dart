import 'dart:convert';

/// The UDP beacon from docs/DEVICE_PROTOCOL.md. The board broadcasts one of
/// these every two seconds; routers that drop mDNS still pass a broadcast.
class BeaconPacket {
  const BeaconPacket({
    required this.deviceId,
    required this.ip,
    this.name,
    this.fwVersion,
    this.port = 80,
  });

  static const udpPort = 7332;

  final String deviceId;
  final String ip;
  final String? name;
  final String? fwVersion;
  final int port;

  String get host => port == 80 ? ip : '$ip:$port';

  /// Null for anything that is not an Orion beacon. Stray broadcasts on this
  /// port are normal on a home LAN, so a bad packet is silence, not an error.
  static BeaconPacket? parse(List<int> datagram) {
    if (datagram.isEmpty || datagram.length > 4096) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(datagram, allowMalformed: true));
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['orion'] != 1) return null;
    final id = decoded['device_id'];
    final ip = decoded['ip'];
    if (id is! String || id.isEmpty || ip is! String || ip.isEmpty) return null;
    final port = decoded['port'];
    return BeaconPacket(
      deviceId: id,
      ip: ip,
      name: decoded['name'] is String ? decoded['name'] as String : null,
      fwVersion: decoded['fw'] is String ? decoded['fw'] as String : null,
      port: port is num ? port.toInt() : 80,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'orion': 1,
    'device_id': deviceId,
    if (name != null) 'name': name,
    if (fwVersion != null) 'fw': fwVersion,
    'ip': ip,
    'port': port,
  };
}
