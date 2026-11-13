import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/dsh/bundled_node.dart';
import 'package:orion/features/harness/data/dsh/dsh_probe.dart';
import 'package:orion/features/harness/data/native_tools/process_runner.dart';

class _Runner implements ProcessRunner {
  _Runner(this.answer);

  ProcResult Function(String exe, List<String> args) answer;
  final calls = <(String, List<String>, Map<String, String>?)>[];

  @override
  Future<ProcResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    String? workingDirectory,
    Map<String, String>? environment,
    bool shell = false,
  }) async {
    calls.add((executable, arguments, environment));
    return answer(executable, arguments);
  }
}

void main() {
  late Directory temp;

  setUp(() async => temp = await Directory.systemTemp.createTemp('orion_node'));
  tearDown(() => temp.deleteSync(recursive: true));

  String exeIn(Directory d) => '${d.path}${Platform.pathSeparator}orion.exe';

  test('no node folder next to the app: nothing changes', () {
    expect(BundledNode.dir(executable: exeIn(temp)), isNull);
    expect(BundledNode.environment(executable: exeIn(temp)), isEmpty);
  });

  test('the installer\'s node folder goes first on the PATH', () {
    final sep = Platform.pathSeparator;
    final node = File(
      '${temp.path}${sep}node$sep${Platform.isWindows ? 'node.exe' : 'node'}',
    )..createSync(recursive: true);
    final env = BundledNode.environment(
      executable: exeIn(temp),
      parent: const <String, String>{'PATH': r'C:\Windows'},
    );
    expect(env['PATH'], startsWith(node.parent.path));
    expect(env['PATH'], endsWith(r'C:\Windows'));
    expect(env['NPM_CONFIG_UPDATE_NOTIFIER'], 'false');
  });

  test(
    'the probe passes the environment to node and npx, and fetches the MCP servers',
    () async {
      final runner = _Runner(
        (exe, args) => exe == 'node'
            ? const ProcResult(0, 'v24.22.2', '')
            : const ProcResult(0, '0.2.2-rc.1', ''),
      );
      final probe = DshProbe(
        runner: runner,
        environment: const <String, String>{'PATH': 'X'},
      );
      final v = await probe.versions();
      expect(v.hasDsh, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(runner.calls.every((c) => c.$3?['PATH'] == 'X'), isTrue);
      final fetches = runner.calls
          .map((c) => c.$2.join(' '))
          .where((a) => a.contains('mcp'))
          .toList();
      expect(fetches, isNotEmpty);
      expect(fetches.join('\n'), contains('--package=@playwright/mcp@'));
      // Only fetched, never started: winapp has no --version and would sit
      // on stdin as an MCP server.
      expect(fetches.every((a) => a.endsWith('-- node --version')), isTrue);
    },
  );

  test(
    'a probe that found no dsh is tried again, a good one is kept',
    () async {
      var online = false;
      final runner = _Runner(
        (exe, args) => exe == 'node'
            ? const ProcResult(0, 'v24.22.2', '')
            : online
            ? const ProcResult(0, '0.2.2-rc.1', '')
            : const ProcResult.failed('offline'),
      );
      final probe = DshProbe(
        runner: runner,
        retryAfter: Duration.zero,
        environment: const <String, String>{},
      );
      expect((await probe.versions()).hasDsh, isFalse);
      await Future<void>.delayed(Duration.zero);
      online = true;
      expect((await probe.versions()).hasDsh, isTrue);
      await Future<void>.delayed(Duration.zero);
      final before = runner.calls.where((c) => c.$1 == 'node').length;
      await probe.versions();
      expect(runner.calls.where((c) => c.$1 == 'node').length, before);
    },
  );

  test(
    'a miss is kept for retryAfter, so callers do not each start npx',
    () async {
      final runner = _Runner(
        (exe, args) => exe == 'node'
            ? const ProcResult(0, 'v24.22.2', '')
            : const ProcResult.failed('offline'),
      );
      final probe = DshProbe(
        runner: runner,
        environment: const <String, String>{},
      );
      for (var i = 0; i < 5; i++) {
        expect((await probe.versions()).hasDsh, isFalse);
      }
      expect(runner.calls.where((c) => c.$1 == 'npx'), hasLength(1));
      probe.reset();
      await probe.versions();
      expect(runner.calls.where((c) => c.$1 == 'npx'), hasLength(2));
    },
  );
}
