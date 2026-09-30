import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/device/data/fake_device_client.dart';
import 'package:orion/features/providers/data/http_fish_repository.dart';
import 'package:orion/features/providers/domain/fish_config.dart';

/// Answers dio without a socket, so the shape of every Fish call is a test.
class _CannedAdapter implements HttpClientAdapter {
  _CannedAdapter(this.reply);

  final ResponseBody Function(RequestOptions options) reply;
  final seen = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    seen.add(options);
    return reply(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody _json(Object body, {int status = 200}) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: <String, List<String>>{
    Headers.contentTypeHeader: <String>['application/json'],
  },
);

void main() {
  group('the calls', () {
    late _CannedAdapter adapter;
    late HttpFishRepository fish;

    void arrange(ResponseBody Function(RequestOptions options) reply) {
      adapter = _CannedAdapter(reply);
      final dio = Dio()..httpClientAdapter = adapter;
      fish = HttpFishRepository(
        deviceClient: FakeDeviceClient(autoTurns: false),
        dio: dio,
      );
    }

    test('the key check asks for one of the workspace own voices', () async {
      arrange((_) => _json(<String, dynamic>{'total': 1, 'items': <void>[]}));
      expect((await fish.validateKey('fk-real')).isOk, isTrue);

      final asked = adapter.seen.single;
      expect(asked.uri.path, '/model');
      expect(asked.uri.queryParameters['self'], 'true');
      expect(asked.uri.queryParameters['page_size'], '1');
      expect(asked.headers['authorization'], 'Bearer fk-real');
    });

    test('401 is a bad key, in those words', () async {
      arrange((_) => _json(<String, dynamic>{'detail': 'nope'}, status: 401));
      final failure = (await fish.validateKey('fk-wrong')).failureOrNull;
      expect(failure, isA<ProviderFailure>());
      expect((failure! as ProviderFailure).kind, ProviderFailureKind.badKey);
    });

    test('an empty key never leaves the app', () async {
      arrange((_) => _json(const <String, dynamic>{}));
      expect((await fish.validateKey('  ')).isErr, isTrue);
      expect(adapter.seen, isEmpty);
    });

    test('a preview asks for balanced mp3 with the chosen voice', () async {
      arrange((_) => ResponseBody.fromBytes(<int>[0xFF, 0xFB, 0x90], 200));
      final bytes = await fish.previewVoice(
        const FishConfig(
          apiKey: 'fk-real',
          voiceId: 'v1',
          ttsModel: 's2.1-pro',
        ),
      );
      expect(bytes.getOrThrow(), hasLength(3));

      final asked = adapter.seen.single;
      final body = asked.data! as Map<String, dynamic>;
      expect(body['format'], 'mp3');
      expect(body['latency'], 'balanced');
      expect(body['reference_id'], 'v1');
      expect(asked.headers['model'], 's2.1-pro');
    });

    test('no credit says so instead of blaming the key', () async {
      arrange((_) => _json(const <String, dynamic>{}, status: 402));
      final failure =
          (await fish.validateKey('fk-real')).failureOrNull! as ProviderFailure;
      expect(failure.kind, ProviderFailureKind.network);
      expect(failure.message, contains('credit'));
    });
  });
}
