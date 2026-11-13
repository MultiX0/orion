import 'dart:async';
import 'dart:io';

import '../../../providers/domain/llm_provider.dart';
import '../../domain/agent_runtime.dart';
import 'agent_process.dart';
import 'bundled_node.dart';
import 'dsh_config.dart';
import 'dsh_paths.dart';
import 'dsh_probe.dart';
import 'dsh_probe.dart' as dsh_probe show dshPackage, dshVersion;
import 'null_runtime.dart';

/// Runs one task through `dsh --profile headless`. stdout is the answer,
/// stderr is the log. Nothing here is on the app's boot path: if dsh is
/// missing, `isAvailable` is false and the agent_task tool never appears.
///
/// With [desktop] the agent has the whole computer (docs/HARNESS.md, "The
/// PC agent"): it sees the screen and drives the mouse and keyboard through
/// Cua Driver, works in the user's home with full access, and does not ask.
/// The board's approval mode already decided whether the task runs at all.
class DshRuntime implements AgentRuntime {
  DshRuntime({
    required this.paths,
    required this.probe,
    AgentLauncher launcher = spawnProcess,
    DshConfigWriter? config,
    this.desktop = false,
    String? home,
    bool? windows,
  }) : _launch = launcher,
       _config = config ?? DshConfigWriter(paths),
       _home = home ?? DshPaths.userHome(),
       _windows = windows ?? Platform.isWindows;

  /// The pinned dsh (dsh_probe.dart).
  static const dshVersion = dsh_probe.dshVersion;
  static const dshPackage = dsh_probe.dshPackage;

  /// Prepended to every task. The answer is spoken by the board, and nobody
  /// is at the PC to answer a question.
  static const taskPreamble =
      "You are Orion's PC agent with full control of this computer: you can "
      'see the screen and use the mouse and keyboard in any application, run '
      'commands and download files. Do the task yourself, start to finish, '
      'without asking for confirmation; nobody can answer questions.\n'
      'Pick the tool for the job. Anything in a web browser: the playwright '
      'tools (a visible browser window; read the page with browser_snapshot '
      'and act on its elements). A Windows application: the winapp tools '
      '(launch_app or attach_to_pid, get_snapshot, then click_element, '
      'type_text and read_element by automation id). Applications on macOS '
      'or Linux: the cua_driver_native tools. Files, folders, settings and '
      'downloads you know the address of: a shell command is fine and '
      'often faster. After each step check that it worked; if a tool fails, '
      'take a fresh snapshot and try another way.\n'
      'When it is done, or if it cannot be done, reply in one or two short '
      'spoken sentences with no markdown: what you did and where the result '
      'is.\n\n'
      'Task: ';

  final DshPaths paths;
  final DshProbe probe;
  final AgentLauncher _launch;
  final DshConfigWriter _config;
  final String _home;

  /// Windows drives applications through winapp, which needs no install;
  /// elsewhere Cua Driver is installed into the profile first.
  final bool _windows;

  /// Desktop control on: the computer-use plugins, full access, the home
  /// folder.
  final bool desktop;

  /// Set once the desktop plugins are installed in this profile, or failed
  /// to: one try per launch, the agent still runs without them.
  Future<bool>? _desktopReady;

  final _jobs = <String, _Job>{};
  var _counter = 0;

  /// How long a finished job and its log stay readable.
  static const jobKeptFor = Duration(minutes: 10);

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
    // A finished job keeps its log for late listeners a while, then goes:
    // each one holds up to 2000 lines, and the app can run for weeks.
    unawaited(
      job.result.future.then((_) {
        Timer(jobKeptFor, () => _jobs.remove(id));
      }),
    );

    final withCua =
        desktop && !_windows && await (_desktopReady ??= _installDesktop(job));
    final written = await _config.write(
      provider,
      model,
      desktop: desktop,
      cua: withCua,
      windows: _windows,
    );
    if (written.isErr) {
      job.fail(written.failureOrNull!.message);
      return AgentJob(id: id, task: task, done: job.result.future);
    }
    // Full access follows the setting, not the plugins: without Cua Driver
    // the agent still has the shell and the whole home folder.
    unawaited(_drive(job, task, provider.apiKey ?? '', desktop));
    return AgentJob(id: id, task: task, done: job.result.future);
  }

  /// True when the profile has the computer-use plugins, installing them the
  /// first time (a few seconds, through dsh's own plugin manager).
  Future<bool> _installDesktop(_Job job) async {
    final marker = File(
      [
        paths.profileDir(DshConfigWriter.profile),
        'node_modules',
        ...DshConfigWriter.desktopPlugins.last.split('/'),
        'package.json',
      ].join(Platform.pathSeparator),
    );
    if (marker.existsSync()) return true;
    job.log('installing desktop control (Cua Driver) for the agent');
    try {
      await paths.ensureDirectories();
      final process = await _launch(
        'npx',
        <String>[
          '-y',
          dshPackage,
          'plugin',
          '--profile',
          DshConfigWriter.profile,
          'add',
          for (final p in DshConfigWriter.desktopPlugins) '$p@$dshVersion',
        ],
        workingDirectory: paths.sandbox,
        environment: <String, String>{
          ...BundledNode.environment(),
          'DSH_HOME': paths.dshHome,
          'DSH_TELEMETRY_MODE': 'DISABLED',
        },
      );
      final out = process.stdoutLines.listen(job.log).asFuture<void>();
      final err = process.stderrLines.listen(job.log).asFuture<void>();
      final code = await process.exitCode;
      await Future.wait(<Future<void>>[out, err]);
      final ok = code == 0 && marker.existsSync();
      job.log(
        ok
            ? 'desktop control installed'
            : 'desktop control could not be installed (exit $code); '
                  'the agent runs without it',
      );
      return ok;
    } on Object catch (e) {
      job.log('desktop control could not be installed: $e');
      return false;
    }
  }

  /// Everything the job said so far, then what it says next: a listener that
  /// arrives after the plugin install still reads why it failed.
  @override
  Stream<String> logs(String jobId) {
    final job = _jobs[jobId];
    if (job == null) return const Stream<String>.empty();
    StreamSubscription<String>? live;
    late final StreamController<String> out;
    // History and live lines are joined in one synchronous step on listen,
    // so nothing said in between is lost.
    out = StreamController<String>(
      onListen: () {
        job.history.forEach(out.add);
        if (job.lines.isClosed) {
          unawaited(out.close());
          return;
        }
        live = job.lines.stream.listen(out.add, onDone: out.close);
      },
      onCancel: () => live?.cancel(),
    );
    return out.stream;
  }

  @override
  Future<void> cancel(String jobId) async {
    final job = _jobs[jobId];
    if (job == null || job.result.isCompleted) return;
    job.process?.kill();
    job.fail('Cancelled');
  }

  Future<void> _drive(_Job job, String task, String apiKey, bool full) async {
    try {
      final process = await _launch(
        'npx',
        <String>[
          '-y',
          dshPackage,
          '--profile',
          DshConfigWriter.profile,
          if (full) ...<String>[
            '--permission-mode',
            'danger-full-access',
            '--approval-policy',
            'never',
          ],
          '-',
        ],
        stdin: '$taskPreamble$task',
        workingDirectory: full ? _home : paths.sandbox,
        environment: <String, String>{
          // The Node the installer bundles: dsh and every npx it starts.
          ...BundledNode.environment(),
          'DSH_HOME': paths.dshHome,
          // Full control works in the home folder and asks nobody; without
          // it dsh stays inside the sandbox folder we gave it.
          'DSH_PERMISSION_MODE': full
              ? 'danger-full-access'
              : 'workspace-write',
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
  final history = <String>[];
  final result = Completer<AgentResult>();
  AgentProcess? process;

  void log(String line) {
    if (history.length < 2000) history.add(line);
    if (!lines.isClosed) lines.add(line);
  }

  void finish(bool ok, String text) {
    if (result.isCompleted) return;
    result.complete(AgentResult(ok: ok, text: text));
    unawaited(lines.close());
  }

  void fail(String message) => finish(false, message);
}
