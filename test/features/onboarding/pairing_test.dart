import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/beacon_listener.dart';
import 'package:orion/core/network/lan_discovery.dart';
import 'package:orion/core/network/mdns_scanner.dart';
import 'package:orion/core/result.dart';
import 'package:orion/core/storage/in_memory_secret_store.dart';
import 'package:orion/core/storage/secret_store.dart';
import 'package:orion/features/onboarding/data/http_pairing_repository.dart';
import 'package:orion/features/onboarding/data/lan_device_discovery.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/camera.dart';
import '../../../tool/mock_device/routes.dart';

void main() {
  late MockBoard board;
  late HttpServer server;
  late LanDeviceDiscovery discovery;
  late InMemorySecretStore secrets;

  // No mDNS in a test, the scanner has to stay quiet about it.
  MdnsScanner silentScanner() =>
      MdnsScanner(newClient: () => throw const SocketException('no mdns'));

  setUp(() async {
    board = MockBoard();
    final routes = MockRoutes(board, MockCamera(FrameStore(const [])));
    server = await shelf_io.serve(routes.handler, 'localhost', 0);
    discovery = LanDeviceDiscovery(
      buildDiscovery: (confirm) => LanDiscovery(
        confirm: confirm,
        mdns: silentScanner(),
        // Port 0 binds an ephemeral socket, so no beacon ever arrives.
        beacon: BeaconListener(port: 0),
        nameHints: ['localhost:${server.port}'],
        sweepAddresses: const [],
      ),
    );
    secrets = InMemorySecretStore();
  });

  tearDown(() async {
    await board.dispose();
    await server.close(force: true);
  });

  test('discovery finds the board on a known host', () async {
    final devices = await discovery.discover().first;
    expect(devices, hasLength(1));
    expect(devices.single.id, 'orion-a1b2');
    expect(devices.single.host, 'localhost:${server.port}');
    expect(devices.single.fwVersion, '0.1.0-mock');
  });

  test('a host that is not a board is a failure, not a device', () async {
    final result = await discovery.probe('localhost:1');
    expect(result.failureOrNull, isA<NetworkFailure>());
  });

  test(
    'pairing provisions the board and stores the token',
    () async {
      final pairing = HttpPairingRepository(
        secrets: secrets,
        discovery: discovery,
        waitForBoard: const Duration(seconds: 5),
      );

      final result = await pairing.pair(
        host: 'localhost:${server.port}',
        wifiSsid: 'home',
        wifiPassword: 'hunter2',
        deviceName: 'Orion',
      );

      final device = result.getOrThrow();
      expect(device.id, 'orion-a1b2');

      final stored = await secrets.read(SecretKeys.pairingToken);
      expect(stored, isNotNull);
      expect(stored, hasLength(32));
      expect(board.appToken, stored, reason: 'the board got the same token');
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('the token is fresh every time', () async {
    final pairing = HttpPairingRepository(
      secrets: secrets,
      discovery: discovery,
      waitForBoard: Duration.zero,
    );
    await pairing.pair(
      host: 'localhost:${server.port}',
      wifiSsid: 'home',
      wifiPassword: 'hunter2',
      deviceName: 'Orion',
    );
    final first = board.appToken;

    await pairing.pair(
      host: 'localhost:${server.port}',
      wifiSsid: 'home',
      wifiPassword: 'hunter2',
      deviceName: 'Orion',
    );
    expect(board.appToken, isNot(first));
  });
}
