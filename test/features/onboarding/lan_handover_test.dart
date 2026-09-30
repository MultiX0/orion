import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/core/network/lan_discovery.dart';
import 'package:orion/core/result.dart';
import 'package:orion/core/storage/in_memory_secret_store.dart';
import 'package:orion/core/storage/secret_store.dart';
import 'package:orion/features/onboarding/data/http_wifi_change_repository.dart';
import 'package:orion/features/onboarding/data/lan_device_discovery.dart';
import 'package:orion/features/onboarding/data/lan_handover.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/camera.dart';
import '../../../tool/mock_device/routes.dart';

void main() {
  late MockBoard board;
  late HttpServer server;
  late String host;
  late LanDeviceDiscovery discovery;

  setUp(() async {
    board = MockBoard();
    final routes = MockRoutes(board, MockCamera(FrameStore(const [])));
    server = await shelf_io.serve(routes.handler, 'localhost', 0);
    host = 'localhost:${server.port}';
    discovery = LanDeviceDiscovery(
      buildDiscovery: (confirm) => LanDiscovery(confirm: confirm),
    );
  });

  tearDown(() async {
    await board.dispose();
    await server.close(force: true);
  });

  group('handover', () {
    test('finds the board at the address it reported', () async {
      final handover = LanHandover(discovery: discovery);
      final found = await handover.find(
        deviceId: 'orion-a1b2',
        ip: host,
        name: 'Orion',
      );
      expect(found.found, isTrue);
      expect(found.device.id, 'orion-a1b2');
      expect(found.device.host, host);
    });

    test('falls back to the reported address when nothing answers', () async {
      final handover = LanHandover(
        discovery: discovery,
        patience: const Duration(milliseconds: 50),
        every: const Duration(milliseconds: 10),
      );
      final found = await handover.find(
        deviceId: 'orion-zzzz',
        ip: 'localhost:1',
        name: 'Desk',
      );
      expect(found.found, isFalse);
      expect(found.device.host, 'localhost:1');
      expect(found.device.name, 'Desk');
    });
  });

  group('change Wi-Fi over the LAN', () {
    test('posts the network with the token and the board agrees', () async {
      final secrets = InMemorySecretStore();
      await secrets.write(SecretKeys.pairingToken, 'the-token');
      board.appToken = 'the-token';
      final api = DeviceApi(host: host);
      addTearDown(api.close);
      final repo = HttpWifiChangeRepository(api: api, secrets: secrets);

      final result = await repo.changeOverLan(ssid: 'Hearth', password: 'pw');
      expect(result.isOk, isTrue);
      expect(board.appToken, 'the-token');
    });

    test('with no token on file it is an auth failure', () async {
      final api = DeviceApi(host: host);
      addTearDown(api.close);
      final repo = HttpWifiChangeRepository(
        api: api,
        secrets: InMemorySecretStore(),
      );
      final result = await repo.changeOverLan(ssid: 'Hearth', password: 'pw');
      expect(result.failureOrNull, isA<AuthFailure>());
    });
  });
}
