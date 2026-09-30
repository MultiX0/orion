import 'dart:io';

/// One IPv4 address on this machine, with the adapter it belongs to.
class LocalNic {
  const LocalNic(this.name, this.address);

  final String name;
  final String address;

  @override
  String toString() => '$name $address';
}

/// Which addresses this PC owns and which /24 hosts are worth knocking on.
/// Hyper-V, WSL, VirtualBox and VMware adapters sort last: a board is never
/// on one, and sweeping them wastes the three seconds discovery has.
abstract final class NetInterfaces {
  static const _virtualHints = <String>[
    'hyper-v',
    'vethernet',
    'wsl',
    'virtualbox',
    'vmware',
    'vmnet',
    'docker',
    'loopback',
    'bluetooth',
    'tailscale',
    'zerotier',
    'tap-',
    'tun',
  ];

  static bool isVirtual(String interfaceName) {
    final name = interfaceName.toLowerCase();
    return _virtualHints.any(name.contains);
  }

  /// Every host on the same /24 except this machine, .1 through .254.
  static List<String> hostsFor(String ipv4) {
    final parts = ipv4.split('.');
    if (parts.length != 4) return const <String>[];
    final last = int.tryParse(parts[3]);
    if (last == null) return const <String>[];
    final prefix = '${parts[0]}.${parts[1]}.${parts[2]}';
    return <String>[
      for (var i = 1; i <= 254; i++)
        if (i != last) '$prefix.$i',
    ];
  }

  /// Default route first, then real adapters, then virtual ones.
  static List<LocalNic> order(List<LocalNic> nics, {String? preferred}) {
    final sorted = <LocalNic>[...nics];
    sorted.sort((a, b) {
      final rankA = _rank(a, preferred);
      final rankB = _rank(b, preferred);
      return rankA != rankB ? rankA - rankB : a.address.compareTo(b.address);
    });
    return sorted;
  }

  static int _rank(LocalNic nic, String? preferred) {
    if (preferred != null && nic.address == preferred) return 0;
    return isVirtual(nic.name) ? 2 : 1;
  }

  static Future<List<LocalNic>> list() async {
    final List<NetworkInterface> interfaces;
    try {
      interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
    } on SocketException {
      return const <LocalNic>[];
    }
    return <LocalNic>[
      for (final nic in interfaces)
        for (final addr in nic.addresses)
          if (!addr.isLoopback && !addr.isLinkLocal)
            LocalNic(nic.name, addr.address),
    ];
  }

  /// The addresses a sweep should use, best first and capped.
  static Future<List<String>> sweepAddresses({
    String? preferred,
    int max = 3,
  }) async {
    final ordered = order(await list(), preferred: preferred);
    return ordered.take(max).map((n) => n.address).toList();
  }
}
