import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/local_address.dart';

void main() {
  test('route print picks the LAN card, not the Hyper-V one', () {
    final output = File('test/fixtures/route_print_win.txt').readAsStringSync();
    // 172.30.48.1 in that fixture is the Hyper-V adapter, which a board
    // cannot reach. The 0.0.0.0 route points at the real card.
    expect(LocalAddress.parseRoutePrint(output), '172.16.0.244');
  });

  test('a machine with no default route has no answer', () {
    expect(LocalAddress.parseRoutePrint(''), isNull);
    expect(
      LocalAddress.parseRoutePrint('Network Destination Netmask Gateway'),
      isNull,
    );
  });

  test('the lowest metric wins when two cards claim the default', () {
    const output = '''
Network Destination        Netmask          Gateway       Interface  Metric
          0.0.0.0          0.0.0.0      192.168.1.1     192.168.1.20     55
          0.0.0.0          0.0.0.0       10.99.0.1        10.99.0.7     25
''';
    expect(LocalAddress.parseRoutePrint(output), '10.99.0.7');
  });

  test('ip route reads src off the default line', () {
    final output = File('test/fixtures/ip_route_linux.txt').readAsStringSync();
    expect(LocalAddress.parseIpRoute(output), '192.168.1.23');
    expect(LocalAddress.parseIpRoute('172.17.0.0/16 dev docker0'), isNull);
  });

  test('a TCP connection to a listening socket gives the local end', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) => socket.destroy());
    final address = await LocalAddress.towards('127.0.0.1:${server.port}');
    await server.close();
    expect(address, '127.0.0.1');
  });

  test('a board that is not there gives nothing, not a throw', () async {
    final address = await LocalAddress.towards(
      '127.0.0.1:1',
      timeout: const Duration(milliseconds: 300),
    );
    expect(address, isNull);
  });

  test(
    'base_url falls back to the default route when the board is away',
    () async {
      final url = await LocalAddress.baseUrlFor(
        port: 7331,
        boardHost: '127.0.0.1:1',
        run: (exe, args) async =>
            File('test/fixtures/ip_route_linux.txt').readAsStringSync(),
      );
      // On Windows the runner is route print, so only the shape is fixed here.
      expect(url, matches(RegExp(r'^http://\d+\.\d+\.\d+\.\d+:7331$')));
    },
  );
}
