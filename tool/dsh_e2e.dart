import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orion/features/harness/data/confirmation_queue.dart';
import 'package:orion/features/harness/data/dsh/dsh_paths.dart';
import 'package:orion/features/harness/data/dsh/dsh_probe.dart';
import 'package:orion/features/harness/data/dsh/dsh_runtime.dart';
import 'package:orion/features/harness/data/native_tools/native_tools_factory.dart';
import 'package:orion/features/harness/data/tool_executor.dart';
import 'package:orion/features/harness/data/tool_server.dart';
import 'package:orion/features/harness/domain/approval_mode.dart';
import 'package:orion/features/harness/domain/harness_call.dart';
import 'package:orion/features/providers/data/fake_provider_repository.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

/// Runs one agent_task through the real tool server and the real dsh, the
/// way the board would. Needs a key:
///   DP_ORION_KEY=sk-... dart run tool/dsh_e2e.dart
/// Optional: --base-url, --model, --task. Prints every log line dsh writes.
Future<void> main(List<String> args) async {
  final key = Platform.environment['DP_ORION_KEY'] ?? '';
  if (key.isEmpty) {
    stderr.writeln('Set DP_ORION_KEY first. Nothing was run.');
    exitCode = 2;
    return;
  }
  final provider = LlmProvider(
    id: 'deepseek',
    kind: ProviderKind.custom,
    name: 'DeepSeek',
    baseUrl: _arg(args, '--base-url') ?? 'https://api.deepseek.com/v1',
    apiKey: key,
  );
  final model = _arg(args, '--model') ?? 'deepseek-chat';
  final task =
      _arg(args, '--task') ??
      'create a file named hello.txt containing hello in the agent folder';

  final paths = DshPaths.underUserHome();
  final agent = DshRuntime(paths: paths, probe: DshProbe());
  final versions = await agent.versions();
  _say('dsh ${versions.dsh ?? "missing"}, node ${versions.node ?? "missing"}');
  if (!versions.hasDsh) {
    stderr.writeln('No dsh on this machine. Nothing was run.');
    exitCode = 3;
    return;
  }

  final calls = <String, HarnessCall>{};
  final updates = StreamController<HarnessCall>.broadcast();
  final logs = StreamController<(String, String)>.broadcast();
  final executor = ToolExecutor(
    tools: nativeToolsFor(Platform.operatingSystem),
    agent: agent,
    queue: ConfirmationQueue(),
    brain: () async => (provider, model),
    localApproval: () => ApprovalMode.auto,
    describe: FakeProviderRepository(),
    onUpdate: (call) {
      calls[call.callId] = call;
      updates.add(call);
      _say('${call.name} is ${call.status.name}');
    },
    onAgentLog: (jobId, line) => _say('  $jobId | $line'),
  );

  const token = 'e2e-token';
  final server = ToolServer(
    catalog: executor.catalog,
    start: executor.start,
    lookup: (id) => calls[id],
    updates: updates.stream,
    agentLogs: logs.stream,
    token: () => token,
    port: 0,
  );
  await server.startServer();
  _say(
    'tool server on 127.0.0.1:${server.boundPort}, sandbox ${paths.sandbox}',
  );

  // Pending and running are both on the way; only these three are an end.
  const ends = {'done', 'error', 'denied'};
  final done = updates.stream.firstWhere(
    (call) => call.callId == 'e2e1' && ends.contains(call.status.name),
  );
  final answer = await _post(server.boundPort!, token, <String, dynamic>{
    'call_id': 'e2e1',
    'turn_id': 't_e2e',
    'name': 'agent_task',
    'args': <String, dynamic>{'task': task},
    'approval': 'auto',
  });
  _say('the board heard: ${jsonEncode(answer)}');

  final finished = await done.timeout(
    const Duration(minutes: 10),
    onTimeout: () => throw TimeoutException('dsh took longer than ten minutes'),
  );
  _say('final: ${finished.status.name}');
  _say(finished.result ?? finished.message ?? '');

  final hello = File('${paths.sandbox}${Platform.pathSeparator}hello.txt');
  _say(
    hello.existsSync()
        ? 'hello.txt says "${hello.readAsStringSync().trim()}"'
        : 'hello.txt is not in the sandbox',
  );

  await server.stopServer();
  await updates.close();
  await logs.close();
}

Future<Map<String, dynamic>> _post(
  int port,
  String token,
  Map<String, dynamic> body,
) async {
  final http = HttpClient();
  try {
    final request = await http.post('127.0.0.1', port, '/tool');
    request.headers
      ..set('content-type', 'application/json')
      ..set('x-orion-token', token);
    request.write(jsonEncode(body));
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return jsonDecode(text) as Map<String, dynamic>;
  } finally {
    http.close(force: true);
  }
}

String? _arg(List<String> args, String name) {
  final at = args.indexOf(name);
  return at < 0 || at + 1 >= args.length ? null : args[at + 1];
}

void _say(String line) => stdout.writeln(
  '${DateTime.now().toIso8601String().substring(11, 19)} $line',
);
