import 'package:multicast_dns/multicast_dns.dart';

/// One service seen on the LAN, with its TXT record flattened to a map.
class MdnsService {
  const MdnsService({
    required this.name,
    required this.host,
    required this.port,
    this.txt = const <String, String>{},
  });

  final String name;
  final String host;
  final int port;
  final Map<String, String> txt;

  String get hostWithPort => port == 80 ? host : '$host:$port';
}

/// Looks for `_orion._tcp` boards. mDNS is blocked on some networks and on
/// some desktops, so a failure here is silence, not an error: onboarding
/// always offers manual entry next to the search.
class MdnsScanner {
  MdnsScanner({MDnsClient Function()? newClient, this.service = '_orion._tcp'})
    : _newClient = newClient ?? MDnsClient.new;

  final MDnsClient Function() _newClient;
  final String service;

  Stream<MdnsService> scan({
    Duration timeout = const Duration(seconds: 8),
  }) async* {
    final MDnsClient client;
    try {
      client = _newClient();
      await client.start();
    } on Object {
      return;
    }
    try {
      await for (final ptr in client.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('$service.local'),
        timeout: timeout,
      )) {
        final found = await _resolve(client, ptr.domainName);
        if (found != null) yield found;
      }
    } on Object {
      return;
    } finally {
      client.stop();
    }
  }

  /// A board that answers the pointer but not the rest is skipped, not fatal.
  Future<MdnsService?> _resolve(MDnsClient client, String domain) async {
    const step = Duration(seconds: 3);
    try {
      final srv = await client
          .lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(domain),
            timeout: step,
          )
          .first;

      final txt = <String, String>{};
      await for (final record in client.lookup<TxtResourceRecord>(
        ResourceRecordQuery.text(domain),
        timeout: step,
      )) {
        for (final line in record.text.split('\n')) {
          final split = line.indexOf('=');
          if (split > 0) {
            txt[line.substring(0, split).trim()] = line.substring(split + 1);
          }
        }
      }

      final ip = await client
          .lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(srv.target),
            timeout: step,
          )
          .first;

      return MdnsService(
        name: txt['name'] ?? domain.split('.').first,
        host: ip.address.address,
        port: srv.port,
        txt: txt,
      );
    } on Object {
      return null;
    }
  }
}
