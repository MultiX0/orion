import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/dsh/agent_process.dart';
import 'package:orion/features/harness/data/dsh/dsh_config.dart';
import 'package:orion/features/harness/data/dsh/dsh_paths.dart';
import 'package:orion/features/harness/data/dsh/dsh_probe.dart';
import 'package:orion/features/harness/data/dsh/dsh_runtime.dart';
import 'package:orion/features/harness/data/dsh/null_runtime.dart';
import 'package:orion/features/harness/data/native_tools/process_runner.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

const _provider = LlmProvider(
  id: 'deepinfra',
  kind: ProviderKind.deepinfra,
  name: 'DeepInfra',
  baseUrl: 'https://api.deepinfra.com/v1/openai',
  apiKey: 'sk-test-not-a-real-key',
);
const _model = 'meta-llama/Llama-3.3-70B-Instruct-Turbo';

String _lf(String s) => s.replaceAll('\r\n', '\n');

class ScriptedRunner implements ProcessRunner {
  ScriptedRunner(this.answers);

  final Map<String, ProcResult> answers;
  final calls = <String>[];

  @override
  Future<ProcResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    String? workingDirectory,
    Map<String, String>? environment,
    bool shell = false,
  }) async {
    calls.add(executable);
    return answers[executable] ?? const ProcResult.failed('not installed');
  }
}

void main() {
  group('settings.yaml', () {
    test('matches the shape dsh documents', () {
      expect(
        DshConfigWriter.settingsYaml(_provider.baseUrl, _model),
        _lf(File('test/fixtures/dsh_settings.yaml').readAsStringSync()),
      );
    });

    test('quotes scalars, so a model id keeps its slashes and colons', () {
      final yaml = DshConfigWriter.settingsYaml(
        'http://localhost:11434/v1',
        "qwen2.5-coder:32b'weird",
      );

      expect(yaml, contains("baseURL: 'http://localhost:11434/v1'"));
      expect(yaml, contains("- id: 'qwen2.5-coder:32b''weird'"));
    });

    test('the key goes to .env by name, never into the yaml', () {
      final yaml = DshConfigWriter.settingsYaml(_provider.baseUrl, _model);

      expect(yaml, contains('apiKeyEnv: DP_ORION_KEY'));
      expect(yaml, isNot(contains('sk-')));
      expect(DshConfigWriter.envFileBody('sk-abc'), 'DP_ORION_KEY=sk-abc\n');
    });
  });

  group('paths', () {
    test('dsh gets its own home under Orion, never the user home', () {
      final paths = DshPaths.underUserHome(
        environment: <String, String>{'HOME': '/home/ada'},
      );
      final sep = Platform.pathSeparator;

      expect(paths.root, '/home/ada${sep}Orion');
      expect(paths.sandbox, endsWith('${sep}agent'));
      expect(paths.dshHome, '${paths.sandbox}$sep.dsh');
      expect(paths.toolLogFile, endsWith('logs${sep}tools.jsonl'));
    });
  });

  group('probe', () {
    test('reads a version out of whatever the tool prints', () {
      expect(DshProbe.parseSemver('v22.19.0\n'), '22.19.0');
      expect(DshProbe.parseSemver('dsh/0.4.1 win32-x64'), '0.4.1');
      expect(DshProbe.parseSemver('0.4.1-preview.2'), '0.4.1-preview.2');
      expect(DshProbe.parseSemver('command not found'), isNull);
      expect(DshProbe.parseSemver(null), isNull);
    });

    test('Node 20 is not enough, 22.19 and 24 are', () {
      expect(DshProbe.nodeIsNewEnough('20.11.1'), isFalse);
      expect(DshProbe.nodeIsNewEnough('22.18.0'), isFalse);
      expect(DshProbe.nodeIsNewEnough('22.19.0'), isTrue);
      expect(DshProbe.nodeIsNewEnough('24.0.0'), isTrue);
      expect(DshProbe.nodeIsNewEnough(null), isFalse);
    });

    test('no Node means we never even try npx', () async {
      final runner = ScriptedRunner(const <String, ProcResult>{});

      final versions = await DshProbe(runner: runner).versions();

      expect(versions.hasNode, isFalse);
      expect(versions.hasDsh, isFalse);
      expect(runner.calls, <String>['node']);
    });

    test('old Node is reported but still stops the probe', () async {
      final runner = ScriptedRunner(const <String, ProcResult>{
        'node': ProcResult(0, 'v20.11.1', ''),
      });

      final versions = await DshProbe(runner: runner).versions();

      expect(versions.node, '20.11.1');
      expect(versions.hasDsh, isFalse);
      expect(runner.calls, <String>['node']);
    });

    test('both present, and the answer is cached', () async {
      final runner = ScriptedRunner(const <String, ProcResult>{
        'node': ProcResult(0, 'v24.2.0', ''),
        'npx': ProcResult(0, '0.4.1', ''),
      });
      final probe = DshProbe(runner: runner);

      await probe.versions();
      final second = await probe.versions();

      expect(second.dsh, '0.4.1');
      expect(runner.calls, <String>['node', 'npx']);
    });
  });

  group('NullRuntime', () {
    test('is never available and says why', () async {
      const runtime = NullRuntime(node: '20.11.1');

      expect(await runtime.isAvailable(), isFalse);
      expect((await runtime.versions()).node, '20.11.1');
      final job = await runtime.run(
        'tidy my desktop',
        provider: _provider,
        model: _model,
      );
      expect((await job.done!).ok, isFalse);
      expect(await runtime.logs('none').toList(), isEmpty);
    });
  });

  group('DshRuntime', () {
    late Directory temp;
    late DshPaths paths;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('orion_dsh');
      paths = DshPaths(temp.path);
    });

    tearDown(() => temp.deleteSync(recursive: true));

    DshRuntime runtimeWith(AgentLauncher launcher) => DshRuntime(
      paths: paths,
      probe: DshProbe(
        runner: ScriptedRunner(const <String, ProcResult>{
          'node': ProcResult(0, 'v24.2.0', ''),
          'npx': ProcResult(0, '0.4.1', ''),
        }),
      ),
      launcher: launcher,
    );

    test('spawns headless, in the sandbox, with the key in the env', () async {
      late List<String> args;
      late String? cwd;
      late Map<String, String>? env;
      final runtime = runtimeWith((
        executable,
        arguments, {
        workingDirectory,
        environment,
      }) async {
        args = <String>[executable, ...arguments];
        cwd = workingDirectory;
        env = environment;
        return AgentProcess(
          stdoutLines: Stream<String>.value('All tidy.'),
          stderrLines: const Stream<String>.empty(),
          exitCode: Future<int>.value(0),
          kill: () {},
        );
      });

      final job = await runtime.run(
        'tidy my desktop',
        provider: _provider,
        model: _model,
      );
      final result = await job.done!;

      expect(args, <String>[
        'npx',
        '-y',
        '@deepseek-ai/dsh',
        '--profile',
        'headless',
        'tidy my desktop',
      ]);
      expect(cwd, paths.sandbox);
      expect(env!['DSH_HOME'], paths.dshHome);
      expect(env!['DSH_PERMISSION_MODE'], 'workspace-write');
      expect(env![DshConfigWriter.apiKeyEnv], _provider.apiKey);
      expect(result.ok, isTrue);
      expect(result.text, 'All tidy.');
      expect(File(paths.settingsFile).existsSync(), isTrue);
    });

    test('a non-zero exit is a failed job, not a thrown error', () async {
      final runtime = runtimeWith(
        (executable, arguments, {workingDirectory, environment}) async =>
            AgentProcess(
              stdoutLines: const Stream<String>.empty(),
              stderrLines: Stream<String>.value('dsh: reasoning: hmm'),
              exitCode: Future<int>.value(1),
              kill: () {},
            ),
      );

      final job = await runtime.run('x', provider: _provider, model: _model);
      final result = await job.done!;

      expect(result.ok, isFalse);
      expect(result.text, contains('exited with code 1'));
    });

    test('a launcher that throws becomes a failed job', () async {
      final runtime = runtimeWith(
        (executable, arguments, {workingDirectory, environment}) async =>
            throw const ProcessException('npx', <String>[]),
      );

      final job = await runtime.run('x', provider: _provider, model: _model);

      expect((await job.done!).ok, isFalse);
    });

    test('stderr and stdout both reach the job log', () async {
      final runtime = runtimeWith(
        (executable, arguments, {workingDirectory, environment}) async =>
            AgentProcess(
              stdoutLines: Stream<String>.fromIterable(<String>['done']),
              stderrLines: Stream<String>.fromIterable(<String>['step one']),
              exitCode: Future<int>.delayed(
                const Duration(milliseconds: 20),
                () => 0,
              ),
              kill: () {},
            ),
      );

      final job = await runtime.run('x', provider: _provider, model: _model);
      final lines = runtime.logs(job.id).toList();
      await job.done;

      expect(await lines, containsAll(<String>['done', 'step one']));
    });
  });
}
