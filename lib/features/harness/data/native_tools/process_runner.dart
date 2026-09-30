import 'dart:async';
import 'dart:io';

/// What a finished process left behind.
class ProcResult {
  const ProcResult(this.exitCode, this.stdout, this.stderr);
  const ProcResult.failed(this.stderr) : exitCode = -1, stdout = '';

  final int exitCode;
  final String stdout;
  final String stderr;

  bool get ok => exitCode == 0;
}

/// Every shell-out in the harness goes through this, so tests can answer
/// without touching the OS.
abstract class ProcessRunner {
  Future<ProcResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    String? workingDirectory,
    Map<String, String>? environment,

    /// Windows needs a shell for .cmd shims like npx, and to find node on
    /// some machines. Native tools keep it off so quoting stays simple.
    bool shell = false,
  });
}

class SystemProcessRunner implements ProcessRunner {
  const SystemProcessRunner();

  @override
  Future<ProcResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    String? workingDirectory,
    Map<String, String>? environment,
    bool shell = false,
  }) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: environment,
        runInShell: shell,
      );
      final out = StringBuffer();
      final err = StringBuffer();
      final reading = <Future<void>>[
        process.stdout.transform(systemEncoding.decoder).forEach(out.write),
        process.stderr.transform(systemEncoding.decoder).forEach(err.write),
      ];
      // A killed child is better than a stuck one. `start` on a name Windows
      // does not know opens a dialog and waits for a person forever.
      var timedOut = false;
      final code = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          process.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
      await Future.wait(
        reading,
      ).timeout(const Duration(seconds: 2), onTimeout: () => const <void>[]);
      if (timedOut) return ProcResult.failed('$executable timed out');
      return ProcResult(code, out.toString(), err.toString());
    } on ProcessException catch (e) {
      return ProcResult.failed(e.message);
    }
  }
}
