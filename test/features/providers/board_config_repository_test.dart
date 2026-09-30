import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/core/storage/in_memory_secret_store.dart';
import 'package:orion/core/storage/secret_store.dart';
import 'package:orion/features/device/domain/device_config.dart';
import 'package:orion/features/device/domain/llm_config.dart';
import 'package:orion/features/device/domain/stage_config.dart';
import 'package:orion/features/onboarding/data/ble/ble_provisioning_repository.dart';
import 'package:orion/features/onboarding/data/ble/fake_provisioning_link.dart';
import 'package:orion/features/onboarding/domain/nearby_board.dart';
import 'package:orion/features/providers/data/http_board_config_repository.dart';
import 'package:orion/features/providers/domain/board_config_repository.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/camera.dart';
import '../../../tool/mock_device/routes.dart';

const _patch = DeviceConfig(
  llm: LlmConfig(provider: 'groq', baseUrl: 'https://g', model: 'llama'),
  stt: SttConfig(provider: 'fish', apiKey: 'fish-key', model: 'transcribe-1'),
  tts: TtsConfig(
    provider: 'fish',
    apiKey: 'fish-key',
    model: 's2.1-pro-free',
    voice: 'v1',
  ),
);

Map<String, dynamic> _block(Map<String, dynamic> config, String name) =>
    config[name]! as Map<String, dynamic>;

void main() {
  late MockBoard board;
  late HttpServer server;
  late DeviceApi api;
  late InMemorySecretStore secrets;
  late BleProvisioningRepository ble;
  late FakeProvisioningLink link;

  Future<HttpBoardConfigRepository> start({bool v1 = false}) async {
    board = MockBoard(configVersion1: v1);
    final routes = MockRoutes(board, MockCamera(FrameStore(const [])));
    server = await shelf_io.serve(routes.handler, 'localhost', 0);
    api = DeviceApi(host: 'localhost:${server.port}');
    secrets = InMemorySecretStore();
    await secrets.write(SecretKeys.pairingToken, 'tok');
    board.appToken = 'tok';
    link = FakeProvisioningLink(step: Duration.zero);
    ble = BleProvisioningRepository(link: link, secrets: secrets);
    return HttpBoardConfigRepository(
      api: api,
      secrets: secrets,
      bluetooth: ble,
    );
  }

  tearDown(() async {
    await api.close();
    await board.dispose();
    await server.close(force: true);
  });

  test(
    'version 2: the three blocks land, keys masked on the way back',
    () async {
      final repo = await start();
      expect((await repo.configVersion()).valueOrNull, 2);
      expect((await repo.send(_patch)).valueOrNull, ConfigRoute.lan);
      expect(_block(board.config, 'llm')['provider'], 'groq');
      expect(_block(board.config, 'stt')['api_key'], 'fish-key');
      expect(_block(board.config, 'tts')['voice'], 'v1');
      final current = (await repo.current()).valueOrNull!;
      expect(current.tts?.apiKey, '...-key');
    },
  );

  test('version 1: llm and fish only', () async {
    final repo = await start(v1: true);
    expect((await repo.configVersion()).valueOrNull, 1);
    expect((await repo.send(_patch)).valueOrNull, ConfigRoute.lanVersion1);
    expect(_block(board.config, 'llm')['model'], 'llama');
    expect(_block(board.config, 'llm').containsKey('provider'), isFalse);
    expect(_block(board.config, 'fish')['api_key'], 'fish-key');
    expect(_block(board.config, 'fish')['voice_id'], 'v1');
    expect(board.config.containsKey('stt'), isFalse);
  });

  test(
    'the test endpoint: ok, 401 for "bad", 402 for Fish "nocredit"',
    () async {
      final repo = await start();
      await repo.send(_patch);
      final ok = (await repo.test('stt')).valueOrNull!;
      expect(ok.ok, isTrue);
      expect(ok.ms, 412);

      await repo.send(
        const DeviceConfig(
          stt: SttConfig(provider: 'fish', apiKey: 'nocredit'),
        ),
      );
      expect((await repo.test('stt')).valueOrNull?.error, 'http_402');

      await repo.send(const DeviceConfig(llm: LlmConfig(apiKey: 'bad')));
      expect((await repo.test('llm')).valueOrNull?.error, 'http_401');

      // 409 during a turn reads as busy, not as a failure.
      await repo.send(const DeviceConfig(tts: TtsConfig(apiKey: 'busy')));
      final busy = (await repo.test('tts')).valueOrNull!;
      expect(busy.ok, isFalse);
      expect(busy.error, 'busy');
    },
  );

  test('an unknown provider is refused and nothing is stored', () async {
    final repo = await start();
    final sent = await repo.send(
      const DeviceConfig(stt: SttConfig(provider: 'whisper-box')),
    );
    expect(sent.isErr, isTrue);
    expect(_block(board.config, 'stt')['provider'], 'fish');
  });

  test(
    'with the setup session open it goes over Bluetooth, in parts',
    () async {
      final repo = await start();
      await ble.connect(
        const NearbyBoard(id: 'AA', name: 'Orion-a1b2'),
        code: '123456',
      );
      await ble.pair(deviceName: 'Orion');
      expect((await repo.send(_patch)).valueOrNull, ConfigRoute.bluetooth);
      expect(link.configWrites, 1, reason: 'short enough to go whole');
      final longUrl = 'https://llm.example/${'v' * 500}';
      final long = await repo.send(
        DeviceConfig(llm: LlmConfig(baseUrl: longUrl)),
      );
      expect(long.valueOrNull, ConfigRoute.bluetooth);
      expect(link.configWrites, greaterThan(3), reason: 'split into parts');
      expect(_block(link.config, 'llm')['base_url'], longUrl);
      expect(_block(link.config, 'tts')['voice'], 'v1');
      expect(_block(link.config, 'stt')['api_key'], 'fish-key');
      expect(
        _block(board.config, 'llm')['provider'],
        'deepinfra',
        reason: 'not LAN',
      );
    },
  );
}
