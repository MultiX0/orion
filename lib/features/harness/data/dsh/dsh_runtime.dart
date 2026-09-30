import 'dart:async';

import '../../../providers/domain/llm_provider.dart';
import '../../domain/agent_runtime.dart';
import 'agent_process.dart';
import 'dsh_config.dart';
import 'dsh_paths.dart';
import 'dsh_probe.dart';
import 'null_runtime.dart';

/// Runs one task through `dsh --profile headless`. stdout is the answer,
/// stderr is the log. Nothing here is on the app's boot path: if dsh is
/// missing, `isAvailable` is false and the agent_task tool never appears.
class DshRuntime implements AgentRuntime {
  DshRuntime({
    required this.paths,
    required this.probe,
    AgentLauncher launcher = spawnProcess,
    DshConfigWriter? config,
  }) : _launch = launcher,
       _config = config ?? DshConfigWriter(paths);

  final DshPaths paths;
  final DshProbe probe;
  final AgentLauncher _launch;
  final DshConfigWriter _config;

  final _jobs = <String, _Job>{};
  var _counter = 0;

  @override
  Future<bool> isAvailable() async => (await probe.versions()).hasDsh;

  @override
  Future<AgentVersions> versions() => probe.versions();

  @override
  Future<AgentJob> run(
    String task, {
    required LlmProvider provider,
    required String model,
  }) async {
    if (!await isAvailable()) {
      // Same answer as NullRuntime. The tool should never have been offered,
      // but a board with a stale tool list must still get a sentence back.
      return const NullRuntime().run(task, provider: provider, model: model);
    }
    final id = 'j${++_counter}';
    final job = _Job(id);
    _jobs[id] = job;

    final written = await _config.write(provider, model);
    if (written.isErr) {
      job.fail(written.failureOrNull!.message);
      return AgentJob(id: id, task: task, done: job.result.future);
    }
    unawaited(_drive(job, task, provider.apiKey ?? ''));
    return AgentJob(id: id, task: task, done: job.result.future);
  }

  @override
  Stream<String> logs(String jobId) =>
      _jobs[jobId]?.lines.stream ?? const Stream<String>.empty();

  @override
  Future<void> cancel(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job.result.isCompleted) return;
    job.process?.kill();
    job.fail('Cancelled');
  }

  Future<void> _drive(_Job job, String task, String apiKey) async {
    try {
      final process = await _launch(
        'npx',
        <String>['-y', '@deepseek-ai/dsh', '--profile', 'headless', task],
        workingDirectory: paths.sandbox,
        environment: <String, String>{
          'DSH_HOME': paths.dshHome,
          // Keeps dsh inside the sandbox folder we gave it.
          'DSH_PERMISSION_MODE': 'workspace-write',
          'DSH_TELEMETRY_MODE': 'DISABLED',
          // By name, never on the command line, so it stays out of ps.
          DshConfigWriter.apiKeyEnv: apiKey,
        },
      );
      job.process = process;

      final answer = StringBuffer();
      final stdoutDone = process.stdoutLines.listen((line) {
        answer.writeln(line);
        job.log(line);
      }).asFuture<void>();
      // dsh streams reasoning to stderr under a "dsh: reasoning:" heading.
      final stderrDone = process.stderrLines.listen(job.log).asFuture<void>();

      final code = await process.exitCode;
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
      final text = answer.toString().trim();
      job.finish(
        code == 0,
        text.isNotEmpty
            ? text
            : 'dsh exited with code $code and said nothing. '
                  'Check ${paths.dshHome} for a startup log.',
      );
    } on Object catch (e) {
      job.fail('Could not start dsh: $e');
    }
  }
}

class _Job {
  _Job(this.id);

  final String id;
  final lines = StreamController<String>.broadcast();
  final result = Completer<AgentResult>();
  AgentProcess? process;

  void log(String line) {
    if (!lines.isClosed) lines.add(line);
  }

  void finish(bool ok, String text) {
    if (result.isCompleted) return;
    result.complete(AgentResult(ok: ok, text: text));
    unawaited(lines.close());
  }

  void fail(String message) => finish(false, message);
}
