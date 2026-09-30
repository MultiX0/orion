import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/features/harness/data/phone_brain_host.dart';

void main() {
  group('phone brain', () {
    late PhoneBrainHost host;
    final opened = <Uri>[];
    late int port;

    setUp(() async {
      opened.clear();
      host = PhoneBrainHost(
        brain: () async => null,
        token: () => 'phone-token',
        launch: (uri) async {
          opened.add(uri);
          return uri.scheme != 'nothing';
        },
        port: 0,
      );
      port = (await host.start())!;
    });

    tearDown(() => host.stop());

    Future<(int, Map<String, dynamic>)> send(
      String method,
      String path, {
      Map<String, dynamic>? body,
      String? token = 'phone-token',
    }) async {
      final client = HttpClient();
      final req = await client.openUrl(
        method,
        Uri.parse('http://127.0.0.1:$port$path'),
      );
      if (token != null) req.headers.set('Authorization', 'Bearer $token');
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode(body));
      }
      final res = await req.close();
      final text = await res.transform(utf8.decoder).join();
      client.close();
      return (res.statusCode, jsonDecode(text) as Map<String, dynamic>);
    }

    test('offers open_link and nothing of the PC', () async {
      final (status, body) = await send('GET', '/tools');
      expect(status, 200);
      final names = [
        for (final t in body['tools'] as List)
          ((t as Map)['function'] as Map)['name'],
      ];
      expect(names, ['open_link']);
    });

    test('opens a link on the phone', () async {
      final (status, body) = await send(
        'POST',
        '/tool',
        body: <String, dynamic>{
          'call_id': 'c1',
          'name': 'open_link',
          'args': <String, dynamic>{'target': 'spotify:track:7kBQS11'},
        },
      );
      expect(status, 200);
      expect(body['status'], 'done');
      expect(opened.single.toString(), 'spotify:track:7kBQS11');
    });

    test('says so when nothing on the phone opens it', () async {
      final (_, body) = await send(
        'POST',
        '/tool',
        body: <String, dynamic>{
          'call_id': 'c2',
          'name': 'open_link',
          'args': <String, dynamic>{'target': 'nothing:here'},
        },
      );
      expect(body['status'], 'error');
    });

    test('refuses the board without the pairing token', () async {
      final (status, _) = await send('GET', '/tools', token: 'wrong');
      expect(status, 401);
    });

    test(
      'a phone with no model set up answers 503, so the board answers',
      () async {
        final (status, _) = await send(
          'POST',
          '/v1/chat/completions',
          body: <String, dynamic>{
            'messages': [
              <String, dynamic>{'role': 'user', 'content': 'Hi'},
            ],
          },
        );
        expect(status, 503);
      },
    );
  });

  group('the link to the board', () {
    test('says which app this is and where its brain listens', () {
      final api = DeviceApi(
        host: '172.16.0.136',
        token: 'abc',
        client: 'phone',
        brain: '172.16.0.50:7331',
      );
      final uri = api.wsUri;
      expect(uri.path, '/ws');
      expect(uri.queryParameters, <String, String>{
        'token': 'abc',
        'client': 'phone',
        'brain': '172.16.0.50:7331',
      });
    });

    test('a PC sends no brain, it has PC control', () {
      final api = DeviceApi(host: '172.16.0.136', token: 'abc', client: 'pc');
      expect(api.wsUri.queryParameters, <String, String>{
        'token': 'abc',
        'client': 'pc',
      });
    });
  });
}
