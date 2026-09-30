import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/device/data/http_device_client.dart';
import 'package:orion/features/providers/data/http_provider_repository.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/camera.dart';
import '../../../tool/mock_device/routes.dart';

/// A stand-in for an OpenAI-compatible provider, so the repository is tested
/// without a key and without the internet.
void main() {
  late HttpServer llm;
  late HttpServer boardServer;
  late MockBoard board;
  late HttpProviderRepository repo;
  late LlmProvider provider;

  setUp(() async {
    llm = await shelf_io.serve(_fakeProvider, 'localhost', 0);
    board = MockBoard();
    boardServer = await shelf_io.serve(
      MockRoutes(board, MockCamera(FrameStore(const []))).handler,
      'localhost',
      0,
    );
    repo = HttpProviderRepository(
      deviceClient: HttpDeviceClient(
        api: DeviceApi(host: 'localhost:${boardServer.port}'),
      ),
    );
    provider = LlmProvider(
      id: 'test',
      kind: ProviderKind.custom,
      name: 'Test',
      baseUrl: 'http://localhost:${llm.port}/v1',
      apiKey: 'sk-good',
    );
  });

  tearDown(() async {
    await llm.close(force: true);
    await board.dispose();
    await boardServer.close(force: true);
  });

  test('lists models from a live endpoint', () async {
    final models = (await repo.listModels(provider)).getOrThrow();
    expect(models.map((m) => m.id), contains('test-model'));
  });

  test('the test call returns the reply text', () async {
    final reply = (await repo.testCompletion(
      provider,
      'test-model',
    )).getOrThrow();
    expect(reply, 'Hi there, glad to meet you.');
  });

  test('a bad key maps to badKey', () async {
    final result = await repo.testCompletion(
      provider.copyWith(apiKey: 'sk-wrong'),
      'test-model',
    );
    final failure = result.failureOrNull;
    expect(failure, isA<ProviderFailure>());
    expect((failure! as ProviderFailure).kind, ProviderFailureKind.badKey);
  });

  test('an unknown model maps to badModel', () async {
    final result = await repo.testCompletion(provider, 'no-such-model');
    final failure = result.failureOrNull! as ProviderFailure;
    expect(failure.kind, ProviderFailureKind.badModel);
    expect(failure.message, contains('no-such-model'));
  });

  test('pushToDevice writes the llm block on the board', () async {
    final result = await repo.pushToDevice(provider, 'test-model');
    expect(result.isOk, isTrue);

    final llmBlock = board.config['llm']! as Map<String, dynamic>;
    expect(llmBlock['model'], 'test-model');
    expect(llmBlock['base_url'], provider.baseUrl);
    expect(llmBlock['api_key'], 'sk-good');
    expect(
      llmBlock['provider'],
      'deepinfra',
      reason: 'a partial push leaves the rest alone',
    );
  });

  test('describeImage sends the png inline and gets a sentence back', () async {
    final said = await repo.describeImage(
      provider,
      'test-model',
      Uint8List.fromList(<int>[137, 80, 78, 71]),
      'Describe what is on this screen in two sentences.',
    );

    expect(said.getOrThrow(), 'A terminal and a browser.');
  });

  test('describeImage on a model that cannot see maps to badModel', () async {
    final said = await repo.describeImage(
      provider,
      'no-such-model',
      Uint8List.fromList(<int>[137]),
      'Describe this.',
    );

    expect(
      (said.failureOrNull! as ProviderFailure).kind,
      ProviderFailureKind.badModel,
    );
  });

  test(
    'mirrorToHarness only runs when the harness handed us a writer',
    () async {
      final phone = HttpProviderRepository(deviceClient: repo.deviceClient);
      expect(
        (await phone.mirrorToHarness(provider, 'test-model')).isOk,
        isTrue,
      );

      final seen = <String>[];
      final desktop = HttpProviderRepository(
        deviceClient: repo.deviceClient,
        harnessMirror: (p, m) async {
          seen.add('${p.id}/$m');
          return const Ok(null);
        },
      );
      expect(
        (await desktop.mirrorToHarness(provider, 'test-model')).isOk,
        isTrue,
      );
      expect(seen, <String>['test/test-model']);
    },
  );
}

Future<Response> _fakeProvider(Request request) async {
  final auth = request.headers['authorization'];
  if (auth != 'Bearer sk-good') {
    return Response(401, body: '{"error":{"message":"bad key"}}');
  }
  if (request.url.path == 'v1/models') {
    return Response.ok(
      jsonEncode(<String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'test-model', 'context_length': 8192},
        ],
      }),
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
  if (request.url.path == 'v1/chat/completions') {
    final body = jsonDecode(await request.readAsString());
    if (body is! Map<String, dynamic> || body['model'] != 'test-model') {
      return Response.notFound('{"error":{"message":"no such model"}}');
    }
    final content = (body['messages']! as List).first as Map<String, dynamic>;
    final sawImage = content['content'] is List;
    return Response.ok(
      jsonEncode(<String, dynamic>{
        'choices': <Map<String, dynamic>>[
          <String, dynamic>{
            'message': <String, String>{
              'role': 'assistant',
              'content': sawImage
                  ? 'A terminal and a browser.'
                  : 'Hi there, glad to meet you.',
            },
          },
        ],
      }),
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
  return Response.notFound('{"error":{"message":"no such model"}}');
}
