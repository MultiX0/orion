import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/pc_brain.dart';
import 'package:orion/features/harness/domain/harness_call.dart';
import 'package:orion/features/harness/domain/harness_call_status.dart';
import 'package:orion/features/harness/domain/tool_request.dart';
import 'package:orion/features/harness/domain/tool_catalog.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

/// A model host that answers each request from a script by model name and
/// remembers what it was asked.
class FakeModels {
  FakeModels(this.script);

  /// model -> the SSE data events for its next answer, one list per call.
  final Map<String, List<List<Map<String, dynamic>>>> script;
  final asked = <String>[];

  /// The raw request bodies, in order.
  final bodies = <String>[];
  late HttpServer server;

  Future<String> start() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((req) async {
      final raw = await utf8.decoder.bind(req).join();
      bodies.add(raw);
      final body = jsonDecode(raw) as Map<String, dynamic>;
      final model = '${body['model']}';
      asked.add(model);
      final events = script[model]!.removeAt(0);
      req.response.headers.contentType = ContentType('text', 'event-stream');
      for (final delta in events) {
        req.response.write(
          'data: ${jsonEncode({
            'choices': [
              {'index': 0, 'delta': delta},
            ],
          })}\n\n',
        );
      }
      req.response.write('data: [DONE]\n\n');
      await req.response.close();
    });
    return 'http://127.0.0.1:${server.port}';
  }
}

Map<String, dynamic> call(String name, Map<String, dynamic> args) => {
  'tool_calls': [
    {
      'index': 0,
      'id': 'c1',
      'function': {'name': name, 'arguments': jsonEncode(args)},
    },
  ],
};

Future<String> spoken(Stream<List<int>> s) async {
  final out = StringBuffer();
  await for (final chunk in s) {
    for (final line in utf8.decode(chunk).split('\n')) {
      if (!line.startsWith('data: {')) continue;
      final choice =
          ((jsonDecode(line.substring(6)) as Map)['choices'] as List).first
              as Map;
      final c = (choice['delta'] as Map?)?['content'];
      if (c is String) out.write(c);
    }
  }
  return out.toString();
}

void main() {
  late FakeModels models;
  late List<String> ran;

  PcBrain brainFor(String baseUrl, {String? thinking}) {
    final provider = LlmProvider(
      id: 'test',
      kind: ProviderKind.custom,
      name: 'Test',
      baseUrl: baseUrl,
      selectedModel: 'fast',
      thinkingModel: thinking,
    );
    return PcBrain(
      brain: () async => (provider, 'fast'),
      catalog: () async => ToolCatalog.control,
      runTool: (ToolRequest r) async {
        ran.add(r.name);
        return HarnessCall(
          callId: r.callId,
          name: r.name,
          args: r.args,
          receivedAt: DateTime.now(),
          status: HarnessCallStatus.done,
          result: 'done',
        );
      },
      updates: const Stream.empty(),
    );
  }

  Map<String, dynamic> ask(String text) => {
    'messages': [
      {'role': 'user', 'content': text},
    ],
  };

  setUp(() => ran = []);
  tearDown(() => models.server.close(force: true));

  test('a plain question stays on the fast model', () async {
    models = FakeModels({
      'fast': [
        [
          {'content': 'Tokyo.'},
        ],
      ],
    });
    final brain = brainFor(await models.start(), thinking: 'thinker');
    final said = await spoken((await brain.open(ask('Capital of Japan?')))!);
    expect(said.trim(), 'Tokyo.');
    expect(models.asked, ['fast']);
  });

  test('acting on the PC hands the turn to the thinking model', () async {
    models = FakeModels({
      'fast': [
        [
          {'content': 'Opening it. '},
          call('open_app', {'name': 'Spotify'}),
        ],
      ],
      'thinker': [
        [
          call('open_app', {'name': 'Spotify'}),
        ],
        [call('open_windows', <String, dynamic>{})],
        [
          {'content': 'Spotify is open.'},
        ],
      ],
    });
    final brain = brainFor(await models.start(), thinking: 'thinker');
    final said = await spoken((await brain.open(ask('Open Spotify')))!);
    expect(models.asked, ['fast', 'thinker', 'thinker', 'thinker']);
    // The fast model's call was dropped, only the thinking model's ran, and
    // its words from a round with tools were never spoken.
    expect(ran, ['open_app', 'open_windows']);
    expect(said, isNot(contains('Opening it')));
    expect(said.trim(), endsWith('Spotify is open.'));
  });

  test('without a thinking model the fast one does the task', () async {
    models = FakeModels({
      'fast': [
        [
          call('open_app', {'name': 'Spotify'}),
        ],
        [call('open_windows', <String, dynamic>{})],
        [
          {'content': 'Spotify is open.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Open Spotify')))!);
    expect(models.asked, ['fast', 'fast', 'fast']);
    expect(ran, ['open_app', 'open_windows']);
    expect(said.trim(), "One moment, I'm on it. Spotify is open.");
  });

  test('out of rounds, the words of a round with tools are never the '
      'answer: a summary is asked for', () async {
    models = FakeModels({
      'fast': [
        for (var i = 0; i < 14; i++)
          [
            {'content': 'Let me look again. '},
            call('ui_look', {'app': 'Spotify'}),
          ],
        [
          {'content': 'I could not find the song.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Play it')))!);
    expect(models.asked, hasLength(15));
    expect(said, isNot(contains('Let me look again')));
    expect(said.trim(), endsWith('I could not find the song.'));
  });

  test('an answer right after acting, unchecked, is sent back once to be '
      'checked', () async {
    models = FakeModels({
      'fast': [
        [
          call('open_link', {'target': 'https://youtube.com/results?q=x'}),
        ],
        [
          {'content': 'I opened the search.'},
        ],
        [
          call('ui_look', {'app': 'Chrome'}),
        ],
        [
          {'content': 'The video is playing.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Play it on YouTube')))!);
    expect(models.asked, hasLength(4));
    expect(ran, ['open_link', 'ui_look']);
    expect(said, isNot(contains('opened the search')));
    expect(said.trim(), "One moment, I'm on it. The video is playing.");
  });

  test('an answer after a check goes out at once', () async {
    models = FakeModels({
      'fast': [
        [
          call('open_app', {'name': 'Spotify'}),
        ],
        [call('open_windows', <String, dynamic>{})],
        [
          {'content': 'Spotify is open.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Open Spotify')))!);
    expect(models.asked, hasLength(3));
    expect(said.trim(), "One moment, I'm on it. Spotify is open.");
  });

  test('the filler goes with a keep-alive that fills a board read', () async {
    models = FakeModels({
      'fast': [
        [
          call('open_app', {'name': 'Spotify'}),
        ],
        [call('open_windows', <String, dynamic>{})],
        [
          {'content': 'Spotify is open.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final raw = await (await brain.open(
      ask('Open Spotify'),
    ))!.map(utf8.decode).join();
    // The board's HTTP client returns a read only once 128 bytes are in.
    final alive = RegExp(r': working +\n\n').firstMatch(raw)!.group(0)!;
    expect(utf8.encode(alive).length, greaterThanOrEqualTo(128));
    expect(raw.indexOf(alive), greaterThan(raw.indexOf('One moment')));
  });

  test('a task says one moment at once; an answer does not', () async {
    models = FakeModels({
      'fast': [
        [
          {'content': 'Tokyo.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Capital of Japan?')))!);
    expect(said.trim(), 'Tokyo.');
  });

  test('a look-up stays on the fast model', () async {
    models = FakeModels({
      'fast': [
        [
          call('weather', {'place': 'Amman'}),
        ],
        [
          {'content': 'Sunny, twenty eight degrees.'},
        ],
      ],
    });
    final brain = brainFor(await models.start(), thinking: 'thinker');
    final said = await spoken((await brain.open(ask('Weather in Amman?')))!);
    expect(models.asked, ['fast', 'fast']);
    expect(said.trim(), 'Sunny, twenty eight degrees.');
  });

  test('a tool name in the answer is never spoken', () async {
    models = FakeModels({
      'fast': [
        [
          call('open_app', {'name': 'Calculator'}),
        ],
        [
          call('ui_look', {'app': 'Calculator'}),
        ],
        [
          {'content': 'I checked with ui_look: the calculator is open.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Open the calculator')))!);
    expect(ran, ['open_app', 'ui_look']);
    expect(said, isNot(contains('ui_look')));
    expect(said.trim(), "One moment, I'm on it. The calculator is open.");
  });

  test('the summary out of rounds is spoken without tool names', () async {
    models = FakeModels({
      'fast': [
        for (var i = 0; i < 14; i++)
          [
            call('ui_look', {'app': 'Spotify'}),
          ],
        [
          {'content': 'I used ui_look to check: the song is not playing.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    final said = await spoken((await brain.open(ask('Play it')))!);
    expect(models.asked, hasLength(15));
    expect(said, isNot(contains('ui_look')));
    expect(said.trim(), endsWith('The song is not playing.'));
  });

  test('the brain is told never to name its tools aloud', () async {
    models = FakeModels({
      'fast': [
        [
          {'content': 'Tokyo.'},
        ],
      ],
    });
    final brain = brainFor(await models.start());
    await spoken((await brain.open(ask('Capital of Japan?')))!);
    expect(models.bodies.single, contains('Never name a tool'));
  });
}
