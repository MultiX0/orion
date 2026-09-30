// Runs the PC brain from the command line against the real model, with a
// stand-in for this PC's tools, and prints what the board would speak.
//
//   dart run tool/pc_brain_probe.dart "What time is it?" "Open Spotify"
//
// The DeepInfra key comes from .env and is never printed.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:orion/features/harness/data/pc_brain.dart';
import 'package:orion/features/harness/domain/harness_call.dart';
import 'package:orion/features/harness/domain/harness_call_status.dart';
import 'package:orion/features/harness/domain/tool_safety.dart';
import 'package:orion/features/harness/domain/tool_spec.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

Future<void> main(List<String> questions) async {
  final key = File('.env')
      .readAsLinesSync()
      .firstWhere((l) => l.startsWith('DEEPINFRA_API_KEY='), orElse: () => '=')
      .split('=')
      .last
      .trim();
  if (key.isEmpty) {
    stderr.writeln('DEEPINFRA_API_KEY is not in .env');
    exit(1);
  }
  // As the board sends it with Fish: the <fish> marker lines go, the voice
  // tag rules stay (cloud_prompt_refresh in the firmware).
  final prompt = File('firmware/assets/system_prompt.txt')
      .readAsStringSync()
      .replaceAll(RegExp(r'^</?fish>\r?\n', multiLine: true), '');
  final updates = StreamController<HarnessCall>.broadcast();
  final brain = PcBrain(
    brain: () async => (
      LlmProvider(
        id: 'deepinfra',
        kind: ProviderKind.deepinfra,
        name: 'DeepInfra',
        baseUrl: 'https://api.deepinfra.com/v1/openai',
        apiKey: key,
      ),
      'google/gemma-4-31B-it-turbo',
    ),
    catalog: () async => const [
      ToolSpec(
        name: 'open_app',
        description: 'Open an installed application by name',
        safety: ToolSafety.safe,
        parameters: {
          'type': 'object',
          'properties': {
            'name': {'type': 'string'},
          },
          'required': ['name'],
        },
      ),
      ToolSpec(
        name: 'system_stats',
        description: 'CPU, RAM, GPU usage and temperatures',
        safety: ToolSafety.safe,
        parameters: {'type': 'object', 'properties': <String, dynamic>{}},
      ),
    ],
    runTool: (req) async {
      stdout.writeln('  [pc tool] ${req.name} ${req.args}');
      return HarnessCall(
        callId: req.callId,
        name: req.name,
        receivedAt: DateTime.now(),
        status: HarnessCallStatus.done,
        result: req.name == 'system_stats'
            ? 'cpu 23%, ram 11.2 of 16 GB (70%), gpu RTX 3050 41% 6 GB, temps cpu 61C gpu 55C'
            : 'Opened ${req.args['name']} (C:/Program Files/${req.args['name']}/app.exe, pid 18344)',
      );
    },
    updates: updates.stream,
  );

  for (final q in questions) {
    stdout.writeln('Q: $q');
    final watch = Stopwatch()..start();
    final stream = await brain.open({
      'model': 'x',
      'stream': true,
      'max_tokens': 200,
      'messages': [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': q},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'look',
            'description':
                'Take a picture with the camera and look at what is in front of the device.',
            'parameters': {'type': 'object', 'properties': <String, dynamic>{}},
          },
        },
      ],
    });
    if (stream == null) {
      stdout.writeln('  no stream (the board would fall back)');
      continue;
    }
    final text = StringBuffer();
    int? first;
    await for (final chunk in stream) {
      final s = utf8.decode(chunk);
      for (final m in RegExp(r'"content":"((?:[^"\\]|\\.)*)"').allMatches(s)) {
        first ??= watch.elapsedMilliseconds;
        text.write(m.group(1));
      }
      if (s.contains('tool_calls')) {
        stdout.writeln('  [back to board] $s'.trim());
      }
    }
    stdout.writeln(
      '  A (${first ?? '-'} ms first, ${watch.elapsedMilliseconds} ms all): ${text.toString().replaceAll(r'\n', ' ')}',
    );
  }
  await updates.close();
  exit(0);
}
