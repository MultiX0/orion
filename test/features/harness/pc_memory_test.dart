import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/pc_memory.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('orion_memory'));
  tearDown(() => dir.deleteSync(recursive: true));

  PcMemory memory() => PcMemory(file: File('${dir.path}/memory.json'));

  test('a turn that acted comes back with its tool calls', () {
    memory().addTurn(
      'Close Chrome.',
      'Closed Chrome.',
      ['close_app {name: Chrome}: Closed 1 window of chrome'],
      calls: [
        {
          'name': 'close_app',
          'args': {'name': 'Chrome'},
          'result': 'Closed 1 window of chrome',
        },
      ],
    );
    // Read back from disk, the way the next start of the app sees it.
    final history = memory().history();
    expect(history.map((m) => m['role']), [
      'user',
      'assistant',
      'tool',
      'assistant',
    ]);
    final call = (history[1]['tool_calls'] as List).single as Map;
    expect((call['function'] as Map)['name'], 'close_app');
    expect((call['function'] as Map)['arguments'], '{"name":"Chrome"}');
    expect(history[2]['tool_call_id'], call['id']);
    expect(history[3]['content'], 'Closed Chrome.');
  });

  test('calls to tools that are gone are left out', () {
    final m = memory()
      ..addTurn(
        'Play Lifetime.',
        'Playing it.',
        const [],
        calls: [
          {'name': 'find_song', 'args': <String, dynamic>{}, 'result': 'x'},
        ],
      )
      ..addTurn('Capital of Japan?', 'Tokyo.', const []);
    final history = m.history(known: {'close_app'});
    expect(history.map((m) => m['role']), [
      'user',
      'assistant',
      'user',
      'assistant',
    ]);
  });
}
