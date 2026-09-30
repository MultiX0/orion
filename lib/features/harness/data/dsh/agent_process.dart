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

typedef AgentLauncher =
    Future<AgentProcess> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

/// Real `Process.start`, split into lines. On Windows `npx` is a .cmd shim,
/// so it only resolves through the shell.
Future<AgentProcess> spawnProcess(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
    runInShell: Platform.isWindows,
  );
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
