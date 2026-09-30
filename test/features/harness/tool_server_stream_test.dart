import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/tool_server.dart';
import 'package:orion/features/harness/domain/harness_call.dart';

void main() {
  test(
    'each piece of a brain reply reaches the board as it is written',
    () async {
      // A reply that sends a keep-alive every 300 ms, the way a task keeps the
      // board's deadline alive while the PC works.
      Stream<List<int>> reply() async* {
        for (var i = 0; i < 4; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          yield utf8.encode(': working\n\n');
        }
        yield utf8.encode('data: [DONE]\n\n');
      }

      final server = ToolServer(
        catalog: () async => const [],
        start: (_) => throw UnimplementedError(),
        lookup: (_) => null,
        updates: const Stream<HarnessCall>.empty(),
        agentLogs: const Stream.empty(),
        token: () => 'tok',
        chat: (_) async => reply(),
        port: 0,
      );
      await server.startServer();
      addTearDown(server.stopServer);

      final http = HttpClient();
      addTearDown(http.close);
      final request = await http.post(
        '127.0.0.1',
        server.boundPort!,
        '/v1/chat/completions',
      );
      request.headers.set('Authorization', 'Bearer tok');
      request.write('{"messages":[]}');
      final response = await request.close();
      final t0 = DateTime.now();
      final arrivals = <int>[];
      await for (final chunk in response) {
        if (utf8.decode(chunk).contains('working')) {
          arrivals.add(DateTime.now().difference(t0).inMilliseconds);
        }
      }
      // Not all at the end: the first keep-alive is in well before the last.
      expect(arrivals, isNotEmpty);
      expect(arrivals.first, lessThan(700), reason: 'arrivals $arrivals');
    },
  );
}
