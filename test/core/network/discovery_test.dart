import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/beacon.dart';
import 'package:orion/core/network/beacon_listener.dart';
import 'package:orion/core/network/device_probe.dart';
import 'package:orion/core/network/lan_discovery.dart';
import 'package:orion/core/network/mdns_scanner.dart';
import 'package:orion/core/network/net_interfaces.dart';
import 'package:orion/core/network/task_pool.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/device/domain/device.dart';

import '../../../tool/mock_device/beacon.dart';

/// Hands back a fixed list instead of listening on UDP 7332.
class _ScriptedBeacon extends BeaconListener {
  _ScriptedBeacon(this.packets);

  final List<BeaconPacket> packets;

  @override
  Stream<BeaconPacket> listen() => Stream<BeaconPacket>.fromIterable(packets);
}

MdnsScanner _silentMdns() =>
    MdnsScanner(newClient: () => throw const SocketException('no mdns here'));

void main() {
  final fixture = File('test/fixtures/beacons.jsonl').readAsLinesSync();

  group('beacon packets', () {
    test('a real beacon parses', () {
      final packet = BeaconPacket.parse(utf8.encode(fixture[0]))!;
      expect(packet.deviceId, 'orion-a1b2');
      expect(packet.name, 'Orion');
      expect(packet.fwVersion, '0.1.0');
      expect(packet.ip, '192.168.1.40');
      expect(packet.port, 80);
      expect(packet.host, '192.168.1.40');
    });

    test('a non default port shows up in the host', () {
      final packet = BeaconPacket.parse(utf8.encode(fixture[1]))!;
      expect(packet.host, '192.168.1.57:8080');
    });

    test('name, fw and port are optional', () {
      final packet = BeaconPacket.parse(utf8.encode(fixture[2]))!;
      expect(packet.deviceId, 'orion-c0de');
      expect(packet.port, 80);
      expect(packet.name, isNull);
    });

    test('anything else on the port is ignored', () {
      for (final line in fixture.sublist(3)) {
        expect(
          BeaconPacket.parse(utf8.encode(line)),
          isNull,
          reason: 'should not parse: $line',
        );
      }
      expect(BeaconPacket.parse(const <int>[]), isNull);
      expect(BeaconPacket.parse(const <int>[0xFF, 0xFE, 0x00]), isNull);
    });
  });

  test(
    'the listener reads a datagram the mock sent',
    () async {
      final probe = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      final port = probe.port;
      probe.close();

      final packets = <BeaconPacket>[];
      final sub = BeaconListener(port: port).listen().listen(packets.add);
      final beacon = MockBeacon(
        deviceId: 'orion-a1b2',
        name: 'Orion',
        httpPort: 8080,
        port: port,
        broadcastAddress: '127.0.0.1',
      );
      await beacon.start();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      beacon.stop();
      await sub.cancel();

      expect(packets, isNotEmpty);
      expect(packets.first.deviceId, 'orion-a1b2');
      expect(packets.first.port, 8080);
    },
    timeout: const Timeout(Duration(seconds: 15)),
  );

  group('interfaces', () {
    test('a /24 is 253 hosts without this machine', () {
      final hosts = NetInterfaces.hostsFor('192.168.1.20');
      expect(hosts, hasLength(253));
      expect(hosts.first, '192.168.1.1');
      expect(hosts.last, '192.168.1.254');
      expect(hosts, isNot(contains('192.168.1.20')));
    });

    test('nonsense addresses sweep nothing', () {
      expect(NetInterfaces.hostsFor('orion.local'), isEmpty);
      expect(NetInterfaces.hostsFor('192.168.1'), isEmpty);
    });

    test('virtual adapters sort last, the default route first', () {
      final ordered = NetInterfaces.order(const <LocalNic>[
        LocalNic('vEthernet (WSL)', '172.30.0.1'),
        LocalNic('Ethernet', '192.168.1.20'),
        LocalNic('Wi-Fi', '192.168.1.21'),
      ], preferred: '192.168.1.21');
      expect(ordered.map((n) => n.address), <String>[
        '192.168.1.21',
        '192.168.1.20',
        '172.30.0.1',
      ]);
      expect(NetInterfaces.isVirtual('VirtualBox Host-Only Network'), isTrue);
      expect(NetInterfaces.isVirtual('Wi-Fi'), isFalse);
    });
  });

  test('the pool never runs more than its limit at once', () async {
    final pool = TaskPool(4);
    var peak = 0;
    await Future.wait(
      List<int>.generate(40, (i) => i).map(
        (_) => pool.run(() async {
          peak = peak > pool.active ? peak : pool.active;
          await Future<void>.delayed(const Duration(milliseconds: 5));
          return 0;
        }),
      ),
    );
    expect(peak, lessThanOrEqualTo(4));
  });

  group('four sources, one list', () {
    Device board(String id, String host, String source) =>
        Device(id: id, name: 'Orion', host: host, source: source);

    test('a board found twice is shown once, with the first source', () async {
      final asked = <String>[];
      final discovery = LanDiscovery(
        confirm: (host, {String source = 'manual'}) async {
          asked.add('$source $host');
          if (host == '192.168.1.40') {
            return Ok(board('orion-a1b2', host, source));
          }
          if (host == '192.168.1.40:80') {
            return Ok(board('orion-a1b2', host, source));
          }
          return const Err(NetworkFailure('nothing there'));
        },
        mdns: _silentMdns(),
        beacon: _ScriptedBeacon(<BeaconPacket>[
          const BeaconPacket(deviceId: 'orion-a1b2', ip: '192.168.1.40'),
          const BeaconPacket(deviceId: 'orion-a1b2', ip: '192.168.1.40'),
        ]),
        nameHints: const <String>[],
        sweepAddresses: const <String>['192.168.1.20'],
      );

      final found = await discovery.devices().toList();
      expect(found, hasLength(1));
      expect(found.single.id, 'orion-a1b2');
      // Whichever source confirmed it first wins; the point is one card.
      expect(found.single.source, anyOf('beacon', 'sweep'));
      expect(asked, contains('sweep 192.168.1.1'));
      expect(asked.where((a) => a.startsWith('sweep')), hasLength(253));
    });

    test('the sweep finds a board no beacon announced', () async {
      final discovery = LanDiscovery(
        confirm: (host, {String source = 'manual'}) async => host == '10.0.0.7'
            ? Ok(board('orion-9f31', host, source))
            : const Err(NetworkFailure('nothing there')),
        mdns: _silentMdns(),
        beacon: _ScriptedBeacon(const <BeaconPacket>[]),
        nameHints: const <String>['orion.local'],
        sweepAddresses: const <String>['10.0.0.2'],
      );

      final found = await discovery.devices().toList();
      expect(found.single.source, 'sweep');
    });
  });

  test('/api/info turns into a device, anything else does not', () {
    final ok = DeviceProbe.toDevice(
      <String, dynamic>{
        'device_id': 'orion-a1b2',
        'name': 'Orion',
        'fw_version': '0.1.0-mock',
        'hw': 't-cameraplus-s3',
        'ip': '127.0.0.1',
        'uptime_s': 12,
        'has_camera': true,
      },
      'localhost:8080',
      'name',
    );
    expect(ok.getOrThrow().id, 'orion-a1b2');
    expect(ok.getOrThrow().source, 'name');

    final bad = DeviceProbe.toDevice(
      <String, dynamic>{'title': 'some router'},
      '192.168.1.1',
      'sweep',
    );
    expect(bad.failureOrNull, isA<ParseFailure>());
  });
}
