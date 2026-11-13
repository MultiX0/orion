import 'dart:async';
import 'dart:io';

import '../../domain/agent_runtime.dart';
import '../native_tools/process_runner.dart';
import 'bundled_node.dart';
import 'dsh_config.dart';

/// Is Node here, is dsh here, and is Node new enough. A found dsh is
/// remembered, because the first `npx` call can download a package; a miss
/// is asked again after [DshProbe.retryAfter].
/// dsh and its plugins move together: a plugin built for another dsh is
/// refused at install. Pinned, so an update is a deliberate change here.
/// Unpinned, `npx -y @deepseek-ai/dsh` also failed on Windows ("'dsh' is not
/// recognized") where the pinned one ran.
const dshVersion = '0.2.2-rc.1';
const dshPackage = '@deepseek-ai/dsh@$dshVersion';

class DshProbe {
  DshProbe({
    this.runner = const SystemProcessRunner(),
    this.nodeTimeout = const Duration(seconds: 10),
    this.dshTimeout = const Duration(minutes: 10),
    this.retryAfter = const Duration(minutes: 5),
    Map<String, String>? environment,
  }) : _env = environment;

  final ProcessRunner runner;
  final Duration nodeTimeout;

  /// Generous: on a new PC the first `npx` downloads dsh before it prints
  /// anything, which took 187 s on a fresh npm cache.
  final Duration dshTimeout;

  /// How long a miss is kept. A PC that cannot reach npm would otherwise
  /// start a new `npx` for every caller.
  final Duration retryAfter;

  /// Null: the bundled Node, when there is one (BundledNode).
  final Map<String, String>? _env;
  Map<String, String> get _environment => _env ?? BundledNode.environment();

  Future<AgentVersions>? _pending;

  /// Running since the last probe came back without dsh.
  Stopwatch? _sinceMiss;

  /// dsh needs Node ^22.19.0 or >=24. Node 20 is not enough.
  static bool nodeIsNewEnough(String? version) {
    final parts = parseSemver(version)?.split('.');
    if (parts == null) return false;
    final major = int.tryParse(parts[0]) ?? 0;
    final minor = int.tryParse(parts[1]) ?? 0;
    if (major >= 24) return true;
    return major == 22 && minor >= 19;
  }

  /// `v22.19.0`, `dsh/0.4.1 win32-x64`, `0.4.1` all give the same answer.
  static String? parseSemver(String? output) {
    if (output == null) return null;
    final match = RegExp(
      r'\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.\-]+)?',
    ).firstMatch(output);
    return match?.group(0);
  }

  /// The answer, probed once. A probe that found no dsh (no internet yet on
  /// a new PC, a download that ran out of time) is kept only for
  /// [retryAfter]; the first ask after that probes again, so the agent does
  /// not stay away until a restart.
  Future<AgentVersions> versions() {
    final pending = _pending;
    final since = _sinceMiss;
    if (pending != null && (since == null || since.elapsed < retryAfter)) {
      return pending;
    }
    _sinceMiss = null;
    late final Future<AgentVersions> mine;
    mine = _probe().then((v) {
      if (!v.hasDsh && identical(_pending, mine)) {
        _sinceMiss = Stopwatch()..start();
      }
      return v;
    });
    return _pending = mine;
  }

  /// Forgets the cached answer, for when the user installs Node and retries.
  void reset() {
    _pending = null;
    _sinceMiss = null;
  }

  Future<AgentVersions> _probe() async {
    final env = _environment;
    final node = await runner.run(
      'node',
      const <String>['--version'],
      timeout: nodeTimeout,
      shell: Platform.isWindows,
      environment: env.isEmpty ? null : env,
    );
    final nodeVersion = node.ok ? parseSemver(node.stdout) : null;
    if (!nodeIsNewEnough(nodeVersion)) {
      return AgentVersions(node: nodeVersion);
    }
    final dsh = await runner.run(
      'npx',
      const <String>['-y', dshPackage, '--version'],
      timeout: dshTimeout,
      shell: Platform.isWindows,
      environment: env.isEmpty ? null : env,
    );
    if (dsh.ok) unawaited(_prewarm(env));
    return AgentVersions(
      node: nodeVersion,
      dsh: dsh.ok ? parseSemver(dsh.stdout) : null,
    );
  }

  /// Fetches the agent's MCP servers in the background, once dsh is there,
  /// so the first spoken task on a new PC does not wait for the downloads.
  /// Only fetched: `node --version` runs in place of the server, because
  /// winapp has no --version and would start serving on stdio. Failures
  /// only mean the first task fetches them itself.
  Future<void> _prewarm(Map<String, String> env) async {
    final packages = <String>[
      DshConfigWriter.playwrightMcp,
      if (Platform.isWindows) DshConfigWriter.winappMcp,
    ];
    for (final p in packages) {
      await runner.run(
        'npx',
        <String>['-y', '--package=$p', '--', 'node', '--version'],
        timeout: dshTimeout,
        shell: Platform.isWindows,
        environment: env.isEmpty ? null : env,
      );
    }
  }
}
