import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/beacon.dart';
import 'package:orion/core/network/beacon_listener.dart';
import 'package:orion/core/network/lan_discovery.dart';
import 'package:orion/core/network/mdns_scanner.dart';
import 'package:orion/core/network/net_interfaces.dart';
import 'package:orion/core/network/orion_link.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/device/data/board_locator.dart';
import 'package:orion/features/device/domain/connection_status.dart';
import 'package:orion/features/device/domain/device.dart';
import 'package:orion/features/harness/data/tool_server.dart';

class _ScriptedBeacon extends BeaconListener {
  _ScriptedBeacon(this.packets);
  final List<BeaconPacket> packets;
  @override
  Stream<BeaconPacket> listen() => Stream<BeaconPacket>.fromIterable(packets);
}

/// A beacon listener that never ends, like the real one on a LAN.
class _OpenBeacon extends BeaconListener {
  final controller = StreamController<BeaconPacket>();
  var cancelled = false;
  @override
  Stream<BeaconPacket> listen() {
    controller.onCancel = () => cancelled = true;
    return controller.stream;
  }
}

MdnsScanner _silentMdns() =>
    MdnsScanner(newClient: () => throw const SocketException('no mdns here'));

const _board = Device(id: 'orion-a1b2', name: 'Orion', host: '192.168.1.40');

void main() {
  group('ids', () {
    test(
      'an install id is its kind and 12 hex digits, and different each time',
      () {
        final a = OrionLink.newId(OrionLink.kindPc);
        final b = OrionLink.newId(OrionLink.kindPc);
        expect(a, matches(RegExp(r'^pc-[0-9a-f]{12}$')));
        expect(a, isNot(b));
        expect(
          OrionLink.newId(OrionLink.kindPhone, Random(1)),
          startsWith('phone-'),
        );
      },
    );

    test('only an id this app made is kept', () {
      expect(OrionLink.isAppId('pc-0123456789ab'), isTrue);
      expect(OrionLink.isAppId('phone-0123456789ab'), isTrue);
      expect(OrionLink.isAppId('orion-a1b2'), isFalse);
      expect(OrionLink.isAppId('pc-xyz'), isFalse);
      expect(OrionLink.isAppId(null), isFalse);
    });
  });

  group('the identity endpoint on the PC and phone server', () {
    late ToolServer server;
    late HttpClient http;

    Future<(int, String)> get(String path, {String? token}) async {
      final req = await http.get('127.0.0.1', server.boundPort!, path);
      if (token != null) req.headers.set('X-Orion-Token', token);
      final res = await req.close();
      return (res.statusCode, await res.transform(utf8.decoder).join());
    }

    ToolServer build({Map<String, dynamic>? Function(int port)? identity}) =>
        ToolServer(
          catalog: () async => const [],
          start: (_) => throw UnimplementedError(),
          lookup: (_) => null,
          updates: const Stream.empty(),
          agentLogs: const Stream.empty(),
          token: () => 'tok-1',
          identity: identity,
          port: 0,
        );

    setUp(() => http = HttpClient());
    tearDown(() async {
      http.close(force: true);
      await server.stopServer();
    });

    test('answers who it is without a token, and nothing else does', () async {
      server = build(
        identity: (port) => OrionLink.identity(
          id: 'pc-0123456789ab',
          kind: OrionLink.kindPc,
          name: 'DESK',
          port: port,
          appVersion: '1.0.0',
        ),
      );
      await server.startServer();
      final (status, body) = await get(OrionLink.wellKnownPath);
      expect(status, 200);
      final me = jsonDecode(body) as Map<String, dynamic>;
      expect(me['id'], 'pc-0123456789ab');
      expect(me['kind'], 'pc');
      expect(me['port'], server.boundPort);
      expect(me['orion'], 1);
      // Still locked: the tools need the token.
      expect((await get('/tools')).$1, 401);
      expect((await get('/tools', token: 'tok-1')).$1, 200);
    });

    test('before the id is ready it says not found, not who it is', () async {
      server = build(identity: (_) => null);
      await server.startServer();
      expect((await get(OrionLink.wellKnownPath)).$1, 404);
    });
  });

  group('following the board to a new address', () {
    test(
      'away long enough: found by id at a new address, the pairing moves',
      () async {
        final moved = Completer<Device>();
        final locator = BoardLocator(
          after: const Duration(milliseconds: 20),
          find: (paired) async =>
              paired.copyWith(host: '192.168.1.41', source: 'beacon'),
          moved: (d) async => moved.complete(d),
        );
        locator.update(_board, ConnectionStatus.reconnecting);
        final now = await moved.future.timeout(const Duration(seconds: 2));
        expect(now.id, 'orion-a1b2');
        expect(now.host, '192.168.1.41');
        locator.dispose();
      },
    );

    test('back before the wait is over: nobody looks', () async {
      var looked = 0;
      final locator = BoardLocator(
        after: const Duration(milliseconds: 40),
        find: (_) async {
          looked++;
          return null;
        },
        moved: (_) async {},
      );
      locator.update(_board, ConnectionStatus.reconnecting);
      locator.update(_board, ConnectionStatus.connected);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(looked, 0);
      locator.dispose();
    });

    test(
      'the same address, or another board, never moves the pairing',
      () async {
        final answers = <Device?>[
          _board,
          const Device(id: 'orion-9999', name: 'Other', host: '192.168.1.50'),
          null,
        ];
        var looked = 0;
        var moves = 0;
        final locator = BoardLocator(
          after: const Duration(milliseconds: 10),
          every: const Duration(milliseconds: 10),
          find: (_) async => looked < answers.length ? answers[looked++] : null,
          moved: (_) async => moves++,
        );
        locator.update(_board, ConnectionStatus.disconnected);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(looked, greaterThanOrEqualTo(3));
        expect(moves, 0);
        locator.dispose();
      },
    );

    test('still away: it keeps looking, and stops once disposed', () async {
      var looked = 0;
      final locator = BoardLocator(
        after: const Duration(milliseconds: 10),
        every: const Duration(milliseconds: 10),
        find: (_) async {
          looked++;
          return null;
        },
        moved: (_) async {},
      );
      locator.update(_board, ConnectionStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(looked, greaterThan(1));
      locator.dispose();
      final at = looked;
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(looked, at);
    });

    test('findBoardById takes only the paired id', () async {
      final found = await findBoardById(
        _board,
        confirm: (host, {String source = 'manual'}) async => switch (host) {
          '192.168.1.50' => const Ok(
            Device(id: 'orion-9999', name: 'Other', host: '192.168.1.50'),
          ),
          '192.168.1.41' => Ok(
            Device(id: 'orion-a1b2', name: 'Orion', host: host, source: source),
          ),
          _ => const Err(NetworkFailure('nothing there')),
        },
        build: (confirm) => LanDiscovery(
          confirm: confirm,
          mdns: _silentMdns(),
          beacon: _ScriptedBeacon(const [
            BeaconPacket(deviceId: 'orion-9999', ip: '192.168.1.50'),
            BeaconPacket(deviceId: 'orion-a1b2', ip: '192.168.1.41'),
          ]),
          nameHints: const [],
          sweepAddresses: const [],
        ),
      );
      expect(found?.host, '192.168.1.41');
    });

    test(
      'findBoardById gives up after its limit and stops listening',
      () async {
        final beacon = _OpenBeacon();
        final found = await findBoardById(
          _board,
          limit: const Duration(milliseconds: 50),
          confirm: (host, {String source = 'manual'}) async =>
              const Err(NetworkFailure('nothing there')),
          build: (confirm) => LanDiscovery(
            confirm: confirm,
            mdns: _silentMdns(),
            beacon: beacon,
            nameHints: const [],
            sweepAddresses: const [],
          ),
        );
        expect(found, isNull);
        expect(beacon.cancelled, isTrue);
      },
    );

    test(
      'a board that still answers at its last address is not searched for',
      () async {
        var built = false;
        final found = await findBoardById(
          _board,
          confirm: (host, {String source = 'manual'}) async =>
              host == _board.host
              ? Ok(_board.copyWith(source: source))
              : const Err(NetworkFailure('nothing there')),
          build: (confirm) {
            built = true;
            return LanDiscovery(
              confirm: confirm,
              mdns: _silentMdns(),
              beacon: _ScriptedBeacon(const []),
              nameHints: const [],
              sweepAddresses: const [],
            );
          },
        );
        expect(found?.host, _board.host);
        expect(built, isFalse);
      },
    );

    test(
      'a hit elsewhere does not move a board that answers at its old address again',
      () async {
        var askedOld = 0;
        final found = await findBoardById(
          _board,
          confirm: (host, {String source = 'manual'}) async {
            if (host == _board.host) {
              // Slow the first time, back by the time discovery is done.
              return ++askedOld == 1
                  ? const Err(NetworkFailure('timed out'))
                  : const Ok(_board);
            }
            if (host == 'orion-a1b2.local') {
              return Ok(_board.copyWith(host: host, source: source));
            }
            return const Err(NetworkFailure('nothing there'));
          },
          build: (confirm) => LanDiscovery(
            confirm: confirm,
            mdns: _silentMdns(),
            beacon: _ScriptedBeacon(const []),
            nameHints: const ['orion-a1b2.local'],
            sweepAddresses: const [],
          ),
        );
        expect(askedOld, 2);
        expect(found?.host, _board.host);
      },
    );

    test(
      'the sweep stays on the board\'s last /24, and needs an IPv4 address',
      () {
        const nics = [
          LocalNic('Wi-Fi', '192.168.1.23'),
          LocalNic('Cellular', '10.20.30.40'),
          LocalNic('vEthernet (WSL)', '172.24.0.1'),
        ];
        expect(NetInterfaces.onSameSubnet('192.168.1.40', nics), [
          '192.168.1.23',
        ]);
        expect(NetInterfaces.onSameSubnet('192.168.1.40:8080', nics), [
          '192.168.1.23',
        ]);
        expect(NetInterfaces.onSameSubnet('192.168.7.40', nics), isEmpty);
        expect(NetInterfaces.onSameSubnet('orion-a1b2.local', nics), isEmpty);
        expect(NetInterfaces.onSameSubnet('localhost:8080', nics), isEmpty);
      },
    );

    test('the move is logged', () async {
      final lines = <String>[];
      final moved = Completer<void>();
      final locator = BoardLocator(
        after: const Duration(milliseconds: 10),
        find: (paired) async =>
            paired.copyWith(host: '192.168.1.41', source: 'beacon'),
        moved: (_) async => moved.complete(),
        log: lines.add,
      );
      locator.update(_board, ConnectionStatus.reconnecting);
      await moved.future.timeout(const Duration(seconds: 2));
      locator.dispose();
      expect(lines.single, contains('orion-a1b2'));
      expect(lines.single, contains('192.168.1.40'));
      expect(lines.single, contains('192.168.1.41'));
    });

    test('the waits between looks double while the board stays away', () async {
      final clock = Stopwatch()..start();
      final at = <int>[];
      final locator = BoardLocator(
        after: const Duration(milliseconds: 5),
        every: const Duration(milliseconds: 50),
        find: (_) async {
          at.add(clock.elapsedMilliseconds);
          return null;
        },
        moved: (_) async {},
      );
      locator.update(_board, ConnectionStatus.disconnected);
      // Looks near 5, 55, 155 and 355 ms. A status change from the reconnect
      // loop does not start the waits over.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      locator.update(_board, ConnectionStatus.reconnecting);
      locator.update(_board, ConnectionStatus.disconnected);
      await Future<void>.delayed(const Duration(milliseconds: 420));
      locator.dispose();
      expect(at.length, greaterThanOrEqualTo(4));
      expect(at[3] - at[2], greaterThan(at[1] - at[0]));
      // Without the doubling there would be ten.
      expect(at.length, lessThan(6));
    });

    test('a live socket starts the waits over', () async {
      var looked = 0;
      final locator = BoardLocator(
        after: const Duration(milliseconds: 5),
        every: const Duration(milliseconds: 100),
        find: (_) async {
          looked++;
          return null;
        },
        moved: (_) async {},
      );
      locator.update(_board, ConnectionStatus.disconnected);
      // Looks near 5, 105 and 305 ms; the next one would be near 705 ms.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(looked, 3);
      locator.update(_board, ConnectionStatus.connected);
      locator.update(_board, ConnectionStatus.reconnecting);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(looked, 4);
      locator.dispose();
    });
  });
}
