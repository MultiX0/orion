import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/dsh/agent_process.dart';
import 'package:orion/features/harness/data/dsh/dsh_config.dart';
import 'package:orion/features/harness/data/dsh/dsh_paths.dart';
import 'package:orion/features/harness/data/dsh/dsh_probe.dart';
import 'package:orion/features/harness/data/dsh/dsh_runtime.dart';
import 'package:orion/features/harness/data/dsh/null_runtime.dart';
import 'package:orion/features/harness/data/confirmation_queue.dart';
import 'package:orion/features/harness/data/native_tools/process_runner.dart';
import 'package:orion/features/harness/data/tool_executor.dart';
import 'package:orion/features/harness/domain/approval_mode.dart';
import 'package:orion/features/providers/data/fake_provider_repository.dart';
import 'package:orion/features/providers/domain/llm_provider.dart';
import 'package:orion/features/providers/domain/provider_kind.dart';

import '../../support/stub_tools.dart';

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

/// A first `npx` that is still downloading dsh.
class _StuckRunner implements ProcessRunner {
  @override
  Future<ProcResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    String? workingDirectory,
    Map<String, String>? environment,
    bool shell = false,
  }) => Completer<ProcResult>().future;
}

void main() {
  group('the profile patch', () {
    test('matches the shape dsh 0.2.2 applies, desktop control included', () {
      expect(
        DshConfigWriter.patchYaml(
          _provider,
          _model,
          desktop: true,
          windows: true,
          downloads: 'C:/Users/ada/Downloads',
        ),
        _lf(File('test/fixtures/dsh_profile_patch.yml').readAsStringSync()),
      );
    });

    test('quotes scalars, so a model id keeps its slashes and colons', () {
      final yaml = DshConfigWriter.patchYaml(
        _provider.copyWith(baseUrl: 'http://localhost:11434/v1'),
        "qwen2.5-coder:32b'weird",
      );

      expect(yaml, contains("baseURL: 'http://localhost:11434/v1'"));
      expect(yaml, contains("- id: 'qwen2.5-coder:32b''weird'"));
    });

    test('the key goes to .env by name, never into the yaml', () {
      final yaml = DshConfigWriter.patchYaml(_provider, _model);

      expect(yaml, contains('apiKeyEnv: DP_ORION_KEY'));
      expect(yaml, isNot(contains('sk-')));
      expect(DshConfigWriter.envFileBody('sk-abc'), 'DP_ORION_KEY=sk-abc\n');
    });

    test(
      'Anthropic and OpenAI use dsh\'s own routes, which know their models',
      () {
        const anthropic = LlmProvider(
          id: 'anthropic',
          kind: ProviderKind.anthropic,
          name: 'Anthropic',
          baseUrl: 'https://api.anthropic.com/v1',
        );
        final a = DshConfigWriter.patchYaml(anthropic, 'claude-haiku-5-5');
        expect(
          a,
          contains('      anthropic:\n        apiKeyEnv: DP_ORION_KEY\n'),
        );
        expect(a, contains('    provider: anthropic\n'));
        expect(a, isNot(contains('openai-completions')));
        expect(a, isNot(contains('baseURL')));

        const openai = LlmProvider(
          id: 'openai',
          kind: ProviderKind.openai,
          name: 'OpenAI',
          baseUrl: 'https://api.openai.com/v1',
        );
        final o = DshConfigWriter.patchYaml(openai, 'gpt-5-mini');
        expect(o, contains('    provider: openai\n'));
        expect(o, isNot(contains('baseURL')));
      },
    );

    test(
      'off Windows: Cua Driver for applications, Chrome for the browser',
      () {
        final yaml = DshConfigWriter.patchYaml(
          _provider,
          _model,
          desktop: true,
          cua: true,
        );
        expect(yaml, contains(DshConfigWriter.desktopPlugins.last));
        expect(yaml, contains("'chrome'"));
        expect(yaml, isNot(contains('winapp')));
      },
    );

    test('every desktop server is pinned to an exact version', () {
      final yaml = DshConfigWriter.patchYaml(
        _provider,
        _model,
        desktop: true,
        windows: true,
      );
      expect(yaml, contains("'${DshConfigWriter.playwrightMcp}'"));
      expect(yaml, contains("'${DshConfigWriter.winappMcp}'"));
      final exact = RegExp(r'@\d+\.\d+\.\d+$');
      expect(DshConfigWriter.playwrightMcp, matches(exact));
      expect(DshConfigWriter.winappMcp, matches(exact));
    });

    test('without desktop control there are no computer-use plugins', () {
      expect(
        DshConfigWriter.patchYaml(_provider, _model),
        isNot(contains('computer-use')),
      );
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
      // One probe; the npx calls after it fetch the MCP servers in the
      // background.
      expect(runner.calls.take(2), <String>['node', 'npx']);
      expect(runner.calls.where((c) => c == 'node'), hasLength(1));
    });

    test(
      'the tool list never waits on a probe that is still running',
      () async {
        final queue = ConfirmationQueue();
        addTearDown(queue.dispose);
        final executor = ToolExecutor(
          tools: StubTools(),
          agent: DshRuntime(
            paths: DshPaths(Directory.systemTemp.path),
            probe: DshProbe(runner: _StuckRunner()),
          ),
          queue: queue,
          brain: () async => null,
          localApproval: () => ApprovalMode.ask,
          describe: FakeProviderRepository(),
          onUpdate: (_) {},
          onAgentLog: (_, _) {},
        );
        final clock = Stopwatch()..start();
        final names = (await executor.catalog()).map((t) => t.name).toList();
        expect(clock.elapsed, lessThan(const Duration(seconds: 2)));
        expect(names, isNot(contains('agent_task')));
        expect(names, contains('open_app'));
      },
    );
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
      late String? given;
      final runtime = runtimeWith((
        executable,
        arguments, {
        workingDirectory,
        environment,
        stdin,
      }) async {
        args = <String>[executable, ...arguments];
        cwd = workingDirectory;
        env = environment;
        given = stdin;
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
        DshRuntime.dshPackage,
        '--profile',
        'headless',
        '-',
      ]);
      // The task travels on stdin, never on a command line cmd would parse.
      expect(given, '${DshRuntime.taskPreamble}tidy my desktop');
      expect(cwd, paths.sandbox);
      expect(env!['DSH_HOME'], paths.dshHome);
      expect(env!['DSH_PERMISSION_MODE'], 'workspace-write');
      expect(env![DshConfigWriter.apiKeyEnv], _provider.apiKey);
      expect(result.ok, isTrue);
      expect(result.text, 'All tidy.');
      expect(File(paths.profilePatch('headless')).existsSync(), isTrue);
    });

    test(
      'desktop control: plugins installed once, then full access in the home folder',
      () async {
        final calls = <(List<String>, String?, Map<String, String>?)>[];
        final runtime = DshRuntime(
          paths: paths,
          desktop: true,
          windows: false,
          home: temp.path,
          probe: DshProbe(
            runner: ScriptedRunner(const <String, ProcResult>{
              'node': ProcResult(0, 'v24.2.0', ''),
              'npx': ProcResult(0, '0.4.1', ''),
            }),
          ),
          launcher:
              (
                executable,
                arguments, {
                workingDirectory,
                environment,
                stdin,
              }) async {
                calls.add((
                  <String>[executable, ...arguments],
                  workingDirectory,
                  environment,
                ));
                if (arguments.contains('plugin')) {
                  // What pnpm leaves behind: the provider's package in the profile.
                  final f = File(
                    [
                      paths.profileDir('headless'),
                      'node_modules',
                      ...DshConfigWriter.desktopPlugins.last.split('/'),
                      'package.json',
                    ].join(Platform.pathSeparator),
                  );
                  f.createSync(recursive: true);
                  f.writeAsStringSync('{}');
                }
                return AgentProcess(
                  stdoutLines: Stream<String>.value(
                    'Downloading it in Chrome.',
                  ),
                  stderrLines: const Stream<String>.empty(),
                  exitCode: Future<int>.value(0),
                  kill: () {},
                );
              },
        );

        final first = await runtime.run(
          'download debian',
          provider: _provider,
          model: _model,
        );
        await first.done;
        final second = await runtime.run(
          'again',
          provider: _provider,
          model: _model,
        );
        await second.done;

        final installs = calls.where((c) => c.$1.contains('plugin')).toList();
        expect(installs, hasLength(1));
        expect(
          installs.single.$1,
          containsAll(<String>[
            DshRuntime.dshPackage,
            'add',
            for (final p in DshConfigWriter.desktopPlugins)
              '$p@${DshRuntime.dshVersion}',
          ]),
        );
        final runs = calls.where((c) => !c.$1.contains('plugin')).toList();
        expect(runs, hasLength(2));
        expect(runs.first.$2, temp.path);
        expect(runs.first.$3!['DSH_PERMISSION_MODE'], 'danger-full-access');
        expect(
          File(paths.profilePatch('headless')).readAsStringSync(),
          contains(DshConfigWriter.desktopPlugins.last),
        );
      },
    );

    test(
      'desktop control that cannot be installed leaves the agent working without it',
      () async {
        final calls = <List<String>>[];
        final runtime = DshRuntime(
          paths: paths,
          desktop: true,
          windows: false,
          home: temp.path,
          probe: DshProbe(
            runner: ScriptedRunner(const <String, ProcResult>{
              'node': ProcResult(0, 'v24.2.0', ''),
              'npx': ProcResult(0, '0.4.1', ''),
            }),
          ),
          launcher:
              (
                executable,
                arguments, {
                workingDirectory,
                environment,
                stdin,
              }) async {
                calls.add(<String>[executable, ...arguments]);
                return AgentProcess(
                  stdoutLines: const Stream<String>.empty(),
                  stderrLines: Stream<String>.value('pnpm: offline'),
                  exitCode: Future<int>.value(
                    arguments.contains('plugin') ? 1 : 0,
                  ),
                  kill: () {},
                );
              },
        );

        await (await runtime.run('x', provider: _provider, model: _model)).done;
        expect(
          File(paths.profilePatch('headless')).readAsStringSync(),
          isNot(contains('computer-use')),
        );
        // Still full access: the setting decides that, not the plugins.
        expect(
          calls.last,
          containsAll(<String>['--permission-mode', 'danger-full-access']),
        );
      },
    );

    test('on Windows: no install, winapp and Edge, full access', () async {
      final calls = <List<String>>[];
      final runtime = DshRuntime(
        paths: paths,
        desktop: true,
        windows: true,
        home: temp.path,
        probe: DshProbe(
          runner: ScriptedRunner(const <String, ProcResult>{
            'node': ProcResult(0, 'v24.2.0', ''),
            'npx': ProcResult(0, '0.4.1', ''),
          }),
        ),
        launcher:
            (
              executable,
              arguments, {
              workingDirectory,
              environment,
              stdin,
            }) async {
              calls.add(<String>[executable, ...arguments]);
              return AgentProcess(
                stdoutLines: Stream<String>.value('Done.'),
                stderrLines: const Stream<String>.empty(),
                exitCode: Future<int>.value(0),
                kill: () {},
              );
            },
      );

      await (await runtime.run('x', provider: _provider, model: _model)).done;
      expect(calls, hasLength(1));
      expect(calls.single, isNot(contains('plugin')));
      expect(
        calls.single,
        containsAll(<String>['--permission-mode', 'danger-full-access']),
      );
      final patch = File(paths.profilePatch('headless')).readAsStringSync();
      expect(patch, contains(DshConfigWriter.winappMcp));
      expect(patch, contains("'msedge'"));
      expect(patch, isNot(contains(DshConfigWriter.desktopPlugins.last)));
    });

    test('a non-zero exit is a failed job, not a thrown error', () async {
      final runtime = runtimeWith(
        (executable, arguments, {workingDirectory, environment, stdin}) async =>
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
        (executable, arguments, {workingDirectory, environment, stdin}) async =>
            throw const ProcessException('npx', <String>[]),
      );

      final job = await runtime.run('x', provider: _provider, model: _model);

      expect((await job.done!).ok, isFalse);
    });

    test('stderr and stdout both reach the job log', () async {
      final runtime = runtimeWith(
        (executable, arguments, {workingDirectory, environment, stdin}) async =>
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
