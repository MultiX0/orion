// Runs one PC agent task through the app's own DshRuntime, desktop control
// on, on this computer. A check for docs/HARNESS.md, "The PC agent".
//
//   ORION_AGENT_KEY=<key> dart run tool/agent_desktop_check.dart <root> "<task>"
//
// <root> is a scratch folder used in place of ~/Orion. The provider is
// Anthropic and the model Claude Haiku 5.5.
import 'dart:io';

import 'package:orion/features/harness/data/dsh/dsh_paths.dart';
import 'package:orion/features/harness/data/dsh/dsh_probe.dart';
import 'package:orion/features/harness/data/dsh/dsh_runtime.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

Future<void> main(List<String> args) async {
  final key = Platform.environment['ORION_AGENT_KEY'];
  if (key == null || args.length < 2) {
    stderr.writeln(
      'usage: ORION_AGENT_KEY=<key> dart run tool/agent_desktop_check.dart <root> "<task>"',
    );
    exit(2);
  }
  final runtime = DshRuntime(
    paths: DshPaths(args[0]),
    probe: DshProbe(),
    desktop: true,
  );
  final started = DateTime.now();
  final job = await runtime.run(
    args[1],
    provider: LlmProvider(
      id: 'anthropic',
      kind: ProviderKind.anthropic,
      name: 'Anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      apiKey: key,
    ),
    model: 'claude-haiku-5-5',
  );
  runtime.logs(job.id).listen((l) => stderr.writeln('  log: $l'));
  final result = await job.done!;
  stdout.writeln(
    'ok=${result.ok} in ${DateTime.now().difference(started).inSeconds} s',
  );
  stdout.writeln(result.text);
  exit(result.ok ? 0 : 1);
}
