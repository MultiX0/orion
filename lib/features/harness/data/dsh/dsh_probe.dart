import 'dart:io';

import '../../domain/agent_runtime.dart';
import '../native_tools/process_runner.dart';

/// Is Node here, is dsh here, and is Node new enough. Answers once and
/// remembers, because the first `npx` call can download a package.
class DshProbe {
  DshProbe({
    this.runner = const SystemProcessRunner(),
    this.nodeTimeout = const Duration(seconds: 10),
    this.dshTimeout = const Duration(seconds: 60),
  });

  final ProcessRunner runner;
  final Duration nodeTimeout;

  /// Generous: a cold `npx` downloads the package before it prints anything.
  final Duration dshTimeout;

  Future<AgentVersions>? _pending;

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

  Future<AgentVersions> versions() => _pending ??= _probe();

  /// Forgets the cached answer, for when the user installs Node and retries.
  void reset() => _pending = null;

  Future<AgentVersions> _probe() async {
    final node = await runner.run(
      'node',
      const <String>['--version'],
      timeout: nodeTimeout,
      shell: Platform.isWindows,
    );
    final nodeVersion = node.ok ? parseSemver(node.stdout) : null;
    if (!nodeIsNewEnough(nodeVersion)) {
      return AgentVersions(node: nodeVersion);
    }
    final dsh = await runner.run(
      'npx',
      const <String>['-y', '@deepseek-ai/dsh', '--version'],
      timeout: dshTimeout,
      shell: Platform.isWindows,
    );
    return AgentVersions(
      node: nodeVersion,
      dsh: dsh.ok ? parseSemver(dsh.stdout) : null,
    );
  }
}
