// Runs the PC brain on plain requests against this PC's real apps and checks
// what actually happened on the screen: is the song playing in Spotify's
// title, is Chrome showing the search, did Notepad get the text. The model
// gets the board's own prompt and nothing else: no recipe per app.
//
//   dart run tool/brain_eval.dart <model> [reasoning_effort]
//
// Reads DEEPINFRA_API_KEY from .env and never prints it. Approval mode is
// auto, as when the user picks "act on your own". Spotify plays for real.
// With --thinking=<model>, the first model answers and hands tasks to the
// second, the way the app runs them. Writes logs/eval/<model>.txt.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orion/features/harness/data/confirmation_queue.dart';
import 'package:orion/features/harness/data/dsh/null_runtime.dart';
import 'package:orion/features/harness/data/native_tools/desktop_control.dart';
import 'package:orion/features/harness/data/native_tools/native_tools_factory.dart';
import 'package:orion/features/harness/data/pc_brain.dart';
import 'package:orion/features/harness/data/pc_memory.dart';
import 'package:orion/features/harness/data/tool_executor.dart';
import 'package:orion/features/harness/domain/approval_mode.dart';
import 'package:orion/features/harness/domain/harness_call.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/features/device/data/http_device_client.dart';
import 'package:orion/features/providers/data/http_provider_repository.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

String _env(String key) {
  for (final line in File('.env').readAsLinesSync()) {
    if (line.startsWith('$key=')) return line.substring(key.length + 1).trim();
  }
  return '';
}

typedef Check = Future<bool> Function(String answer);

class Task {
  const Task(this.say, this.check, {this.before});
  final String say;
  final Check check;
  final Future<void> Function()? before;
}

final control = DesktopControl();

Future<List<String>> windows() => control.openWindows();

Future<bool> titleHas(String app, String text) async => (await windows()).any(
  (w) =>
      w.toLowerCase().startsWith(app.toLowerCase()) &&
      w.toLowerCase().contains(text.toLowerCase()),
);

Future<void> ps(String script) =>
    Process.run('powershell', ['-NoProfile', '-Command', script]);

final tasks = <Task>[
  Task(
    'Play Blinding Lights by The Weeknd on Spotify.',
    (_) async =>
        await titleHas('Spotify', 'Blinding Lights') &&
        await titleHas('Spotify', 'The Weeknd'),
  ),
  Task('Pause the music.', (_) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return (await windows()).any(
      (w) => RegExp(r'^Spotify: Spotify( Free| Premium)?$').hasMatch(w),
    );
  }),
  Task(
    'Open Chrome and search for the best shawarma in Amman.',
    (_) => titleHas('chrome', 'shawarma'),
  ),
  Task('Close Chrome.', (_) async {
    await Future<void>.delayed(const Duration(seconds: 2));
    return !(await windows()).any((w) => w.startsWith('chrome'));
  }),
  Task(
    'شغّل أغنية House of Balloons للويكند على سبوتيفاي',
    (_) => titleHas('Spotify', 'Balloons'),
  ),
  Task(
    'What will the weather be in Irbid tomorrow?',
    (a) async => RegExp(r'\d|degree|twenty|thirty|ten|درجة|عشر').hasMatch(a),
  ),
  // Not Notepad: it reopens with the user's own files, and a test must not
  // type into them.
  Task('افتح الآلة الحاسبة واحسب ١٢٨ ضرب ٤٦', (_) async {
    final look = await control.uiLook('Calculator');
    return look.replaceAll(',', '').contains('Display is 5888');
  }),
];

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: dart run tool/brain_eval.dart <model> [effort] '
      '[--thinking=<model>]',
    );
    exit(64);
  }
  final thinking = args
      .where((a) => a.startsWith('--thinking='))
      .map((a) => a.substring('--thinking='.length))
      .firstOrNull;
  final plain = args.where((a) => !a.startsWith('--')).toList();
  final model = plain[0];
  final effort = plain.length > 1 ? plain[1] : null;
  final provider = LlmProvider(
    id: 'deepinfra',
    kind: ProviderKind.deepinfra,
    name: 'DeepInfra',
    baseUrl: 'https://api.deepinfra.com/v1/openai',
    apiKey: _env('DEEPINFRA_API_KEY'),
    thinkingModel: thinking,
  );
  Future<(LlmProvider, String)?> brain() async => (provider, model);
  final updates = StreamController<HarnessCall>.broadcast();
  final log = StringBuffer();
  final executor = ToolExecutor(
    control: control,
    tools: nativeToolsFor(Platform.operatingSystem),
    agent: const NullRuntime(),
    queue: ConfirmationQueue(),
    brain: brain,
    localApproval: () => ApprovalMode.auto,
    // Real eyes for screenshot; the board client is never called by it.
    describe: HttpProviderRepository(
      deviceClient: HttpDeviceClient(api: DeviceApi(host: '127.0.0.1')),
    ),
    onUpdate: (call) {
      updates.add(call);
      if (call.status.name == 'done' || call.status.name == 'error') {
        final r = (call.result ?? call.message ?? '').replaceAll(
          RegExp(r'\s+'),
          ' ',
        );
        log.writeln(
          '    [${call.name}] ${jsonEncode(call.args)} -> ${r.length > 160 ? '${r.substring(0, 160)}...' : r}',
        );
      }
    },
    onAgentLog: (_, _) {},
  );
  final memFile = File(
    '${Directory.systemTemp.path}/orion_eval_${DateTime.now().millisecondsSinceEpoch}.json',
  );
  final pcBrain = PcBrain(
    brain: brain,
    catalog: executor.catalog,
    runTool: executor.start,
    updates: updates.stream,
    memory: PcMemory(file: memFile),
    desktopState: control.openWindows,
    reasoningEffort: effort,
  );
  // As the board sends it with Fish: the <fish> marker lines go, the voice
  // tag rules stay (cloud_prompt_refresh in the firmware).
  final system = File('firmware/assets/system_prompt.txt')
      .readAsStringSync()
      .replaceAll(RegExp(r'^</?fish>\r?\n', multiLine: true), '');
  var passed = 0;
  var seconds = 0.0;
  log.writeln(
    'model $model${thinking == null ? '' : ' thinking $thinking'}'
    '${effort == null ? '' : ' effort $effort'}',
  );
  for (final (i, t) in tasks.indexed) {
    await t.before?.call();
    final t0 = DateTime.now();
    final stream = await pcBrain.open({
      'messages': [
        {'role': 'system', 'content': system},
        {'role': 'user', 'content': t.say},
      ],
    });
    final said = StringBuffer();
    Duration? first;
    if (stream != null) {
      await for (final chunk in stream) {
        for (final line in utf8.decode(chunk).split('\n')) {
          if (!line.startsWith('data: {')) continue;
          final choice =
              ((jsonDecode(line.substring(6)) as Map)['choices'] as List).first
                  as Map;
          final c = (choice['delta'] as Map?)?['content'];
          if (c is String && c.isNotEmpty) {
            first ??= DateTime.now().difference(t0);
            said.write(c);
          }
        }
      }
    }
    final took = DateTime.now().difference(t0).inMilliseconds / 1000;
    seconds += took;
    final ok = await t.check(said.toString());
    if (ok) passed++;
    // The memory names the model that finished the turn, fast or thinking,
    // and holds the web tools the brain runs itself, which the executor's
    // log never sees.
    var by = '';
    try {
      final turn = (jsonDecode(memFile.readAsStringSync()) as List).last as Map;
      by = ' by ${turn['model']}';
      for (final c in (turn['calls'] as List?) ?? const []) {
        final call = c as Map;
        if (!{'web_search', 'fetch_page', 'weather'}.contains(call['name'])) {
          continue;
        }
        log.writeln(
          '    [${call['name']}] ${jsonEncode(call['args'])} -> ${call['result']}',
        );
      }
    } on Object {
      by = '';
    }
    log.writeln(
      '${ok ? 'PASS' : 'FAIL'} ${i + 1}. ${t.say}$by\n'
      '    said (${first == null ? '-' : '${first.inMilliseconds / 1000}s'} first, ${took}s all): ${said.toString().trim()}',
    );
    stdout.writeln('${ok ? 'PASS' : 'FAIL'} ${i + 1} ${took}s');
  }
  log.writeln(
    'RESULT $passed/${tasks.length} in ${seconds.toStringAsFixed(1)}s',
  );
  Directory('logs/eval').createSync(recursive: true);
  final name = [model, ?thinking].join('+').replaceAll('/', '_');
  File(
    'logs/eval/$name${effort == null ? '' : '_$effort'}.txt',
  ).writeAsStringSync(log.toString());
  stdout.writeln(
    'RESULT $passed/${tasks.length} in ${seconds.toStringAsFixed(1)}s',
  );
  if (memFile.existsSync()) memFile.deleteSync();
  exit(0);
}
