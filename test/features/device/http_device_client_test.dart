import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/camera/data/http_camera_source.dart';
import 'package:orion/features/device/data/http_device_client.dart';
import 'package:orion/features/device/domain/connection_status.dart';
import 'package:orion/features/device/domain/device_mode.dart';
import 'package:orion/features/device/domain/ws_event.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/camera.dart';
import '../../../tool/mock_device/routes.dart';

/// The client talking to the mock board over a real socket on localhost.
void main() {
  late MockBoard board;
  late HttpServer server;
  late DeviceApi api;
  late HttpDeviceClient client;

  setUp(() async {
    board = MockBoard();
    final frames = FrameStore.fromDirectory(
      Directory('tool/mock_device/frames'),
    );
    final routes = MockRoutes(board, MockCamera(frames, fps: 20));
    server = await shelf_io.serve(routes.handler, 'localhost', 0);
    api = DeviceApi(host: 'localhost:${server.port}');
    client = HttpDeviceClient(api: api);
  });

  tearDown(() async {
    await client.dispose();
    await api.close();
    await board.dispose();
    await server.close(force: true);
  });

  test('reads info, state and history', () async {
    final info = (await client.info()).getOrThrow();
    expect(info.deviceId, 'orion-a1b2');

    final state = (await client.state()).getOrThrow();
    expect(state.mode, DeviceMode.idle);

    final turns = (await client.history(limit: 2)).getOrThrow();
    expect(turns, hasLength(2));
    expect(turns.first.transcript, isNotEmpty);
  });

  test('connects and gets the full state on the socket', () async {
    final first = client.events.first;
    await client.connect();
    final event = await first.timeout(const Duration(seconds: 5));

    expect(event, isA<WsStateEvent>());
    expect((event as WsStateEvent).mode, DeviceMode.idle);
    expect(client.connectionStatus, ConnectionStatus.connected);
  });

  test(
    'a talk request drives the turn over the socket',
    () async {
      await client.connect();
      final collected = <WsEvent>[];
      final sub = client.events.listen(collected.add);

      final turnId = (await client.talk(text: 'hello there')).getOrThrow();
      await Future<void>.delayed(const Duration(seconds: 6));
      await sub.cancel();

      expect(collected.whereType<WsTurnStartEvent>().single.turnId, turnId);
      expect(
        collected.whereType<WsTurnTranscriptEvent>().single.text,
        'hello there',
      );
      expect(collected.whereType<WsTurnEndEvent>(), isNotEmpty);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test('a wrong token maps to AuthFailure', () async {
    await client.talk(text: 'set the token');
    board.stopTurn();
    board.appToken = 'the-right-one';
    api.token = 'the-wrong-one';

    final result = await client.state();
    expect(result.failureOrNull, isA<AuthFailure>());
  });

  test('an unreachable board maps to a NetworkFailure, not a crash', () async {
    final dead = DeviceApi(host: 'localhost:1');
    final result = await HttpDeviceClient(api: dead).info();
    expect(result.isErr, isTrue);
    expect(result.failureOrNull, isA<NetworkFailure>());
    await dead.close();
  });

  test(
    'the camera yields frames and a still',
    () async {
      final camera = HttpCameraSource(api);

      final still = (await camera.capture()).getOrThrow();
      expect(still.bytes.sublist(0, 2), <int>[0xFF, 0xD8]);

      final frames = await camera.frames().take(3).toList();
      expect(frames, hasLength(3));
      expect(frames.last.sequence, 2);
      expect(frames.first.bytes.length, greaterThan(1000));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
