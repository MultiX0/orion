import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A running child process, reduced to what the harness needs. Tests hand in
/// their own launcher and never spawn anything.
class AgentProcess {
  const AgentProcess({
    required this.stdoutLines,
    required this.stderrLines,
    required this.exitCode,
    required this.kill,
  });

  final Stream<String> stdoutLines;
  final Stream<String> stderrLines;
  final Future<int> exitCode;
  final void Function() kill;
}

/// [stdin], when given, is written to the child and closed: how a task
/// reaches dsh (`-` reads it from stdin), so no user text is ever on a
/// command line. On Windows that line goes through cmd, which cuts it at a
/// newline and acts on & | % and quotes inside it.
typedef AgentLauncher =
    Future<AgentProcess> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
      String? stdin,
    });

/// Real `Process.start`, split into lines. On Windows `npx` is a .cmd shim,
/// so it only resolves through the shell.
Future<AgentProcess> spawnProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  String? stdin,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: Platform.isWindows,
  );
  if (stdin != null) {
    process.stdin.add(utf8.encode(stdin));
  }
  // Closed either way: a child waiting on stdin would never finish.
  unawaited(process.stdin.close());
  return AgentProcess(
    stdoutLines: process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream(),
    stderrLines: process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .asBroadcastStream(),
    exitCode: process.exitCode,
    kill: process.kill,
  );
}
