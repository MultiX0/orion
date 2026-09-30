import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/conversation/domain/turn.dart';
import 'package:orion/features/device/domain/device_config.dart';
import 'package:orion/features/device/domain/device_info.dart';
import 'package:orion/features/device/domain/device_mode.dart';
import 'package:orion/features/device/domain/device_state.dart';
import 'package:orion/features/device/domain/ws_event.dart';
import 'package:shelf/shelf.dart';

import '../../tool/mock_device/board.dart';
import '../../tool/mock_device/camera.dart';
import '../../tool/mock_device/routes.dart';

/// The mock board is the contract both sides code against, so the test parses
/// its answers with the app's own models.
void main() {
  late MockBoard board;
  late MockRoutes routes;

  setUp(() {
    board = MockBoard();
    routes = MockRoutes(board, MockCamera(FrameStore(const [])));
  });

  tearDown(() => board.dispose());

  Future<Map<String, dynamic>> get$(String path) async {
    final res = await routes.handler(
      Request('GET', Uri.parse('http://localhost:8080$path')),
    );
    return jsonDecode(await res.readAsString()) as Map<String, dynamic>;
  }

  Future<Response> post(String path, Map<String, dynamic> body) async =>
      routes.handler(
        Request(
          'POST',
          Uri.parse('http://localhost:8080$path'),
          body: jsonEncode(body),
        ),
      );

  test('info parses into DeviceInfo', () async {
    final info = DeviceInfo.fromJson(await get$('/api/info'));
    expect(info.deviceId, 'orion-a1b2');
    expect(info.hw, 't-cameraplus-s3');
    expect(info.hasCamera, isTrue);
  });

  test('state parses into DeviceState', () async {
    final state = DeviceState.fromJson(await get$('/api/state'));
    expect(state.mode, DeviceMode.idle);
    expect(state.volume, 70);
    expect(state.batteryPct, isNull);
  });

  test('config comes back with the api key masked', () async {
    board.mergeConfig(<String, dynamic>{
      'llm': <String, dynamic>{'api_key': 'sk-abcdefgh4f2a'},
    });
    final json = await get$('/api/config');
    final config = DeviceConfig.fromJson(json);
    expect(config.llm?.apiKey, '...4f2a');
    expect(config.llm?.apiKey, isNot(contains('abcdefgh')));
  });

  test('a partial config post merges instead of replacing', () async {
    await post('/api/config', <String, dynamic>{'volume': 40});
    final config = DeviceConfig.fromJson(await get$('/api/config'));
    expect(config.volume, 40);
    expect(config.deviceName, 'Orion');
    expect(config.llm?.model, isNotNull);
  });

  test('the time zone takes a POSIX string and nothing else', () async {
    expect(DeviceConfig.fromJson(await get$('/api/config')).timeZone, 'UTC0');
    final ok = await post('/api/config', <String, dynamic>{
      'time_zone': '<+03>-3',
    });
    expect(ok.statusCode, 200);
    expect(
      DeviceConfig.fromJson(await get$('/api/config')).timeZone,
      '<+03>-3',
    );
    final bad = await post('/api/config', <String, dynamic>{
      'time_zone': 'Asia/Riyadh; rm',
    });
    expect(bad.statusCode, 400);
  });

  test('history parses into Turns, newest first', () async {
    final json = await get$('/api/history?limit=2');
    final turns = [
      for (final t in json['turns'] as List)
        Turn.fromJson(t as Map<String, dynamic>),
    ];
    expect(turns, hasLength(2));
    expect(turns.first.id, 't_00042');
    expect(turns.first.timingsMs?.total, 5200);
  });

  test('provision sets the token and later calls need it', () async {
    final res = await post('/api/provision', <String, dynamic>{
      'wifi_ssid': 'home',
      'wifi_password': 'hunter2',
      'app_token': 'tok_1234567890',
      'device_name': 'Orion',
    });
    expect(res.statusCode, 200);

    final denied = await routes.handler(
      Request('GET', Uri.parse('http://localhost:8080/api/state')),
    );
    expect(denied.statusCode, 401);

    final allowed = await routes.handler(
      Request(
        'GET',
        Uri.parse('http://localhost:8080/api/state'),
        headers: const {'x-orion-token': 'tok_1234567890'},
      ),
    );
    expect(allowed.statusCode, 200);
  });

  test(
    'a turn pushes the whole event sequence',
    () async {
      final seen = <WsEvent>[];
      final sub = board.events.listen(
        (e) => seen.add(WsEvent.fromJson(Map<String, dynamic>.from(e))),
      );
      final res = await post('/api/talk', <String, dynamic>{'text': 'hello'});
      final turnId =
          (jsonDecode(await res.readAsString())
                  as Map<String, dynamic>)['turn_id']
              as String;

      await Future<void>.delayed(const Duration(seconds: 6));
      await sub.cancel();

      expect(seen.whereType<WsTurnStartEvent>().single.turnId, turnId);
      expect(seen.whereType<WsTurnTranscriptEvent>().single.text, 'hello');
      expect(seen.whereType<WsTurnReplyEvent>(), isNotEmpty);
      expect(seen.whereType<WsTtsStartEvent>(), isNotEmpty);
      expect(seen.whereType<WsTtsEndEvent>(), isNotEmpty);
      expect(seen.whereType<WsTurnEndEvent>().single.timingsMs?.total, 5100);

      final modes = seen
          .whereType<WsStateEvent>()
          .map((e) => e.mode)
          .whereType<DeviceMode>()
          .toList();
      expect(
        modes,
        containsAllInOrder(<DeviceMode>[
          DeviceMode.listening,
          DeviceMode.thinking,
          DeviceMode.speaking,
          DeviceMode.idle,
        ]),
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test('a second turn while one runs gets 409', () async {
    await post('/api/talk', <String, dynamic>{'text': 'first'});
    final second = await post('/api/talk', <String, dynamic>{'text': 'second'});
    expect(second.statusCode, 409);
    board.stopTurn();
  });

  test('the camera refuses a second stream viewer', () {
    final camera = MockCamera(FrameStore([Uint8List(2)]));
    expect(camera.stream().statusCode, 200);
    expect(camera.stream().statusCode, 409);
  });
}
