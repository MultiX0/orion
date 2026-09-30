import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/native_tools/app_aliases.dart';
import 'package:orion/features/harness/data/native_tools/file_search.dart';
import 'package:orion/features/harness/data/native_tools/linux_tools.dart';
import 'package:orion/features/harness/data/native_tools/native_tools_factory.dart';
import 'package:orion/features/harness/data/native_tools/process_runner.dart';
import 'package:orion/features/harness/data/native_tools/unsupported_tools.dart';
import 'package:orion/features/harness/data/native_tools/windows_tools.dart';
import 'package:orion/features/harness/domain/media_action.dart';
import 'package:orion/features/harness/domain/native_tools.dart';

/// Records what would have been run and answers from a script.
class FakeRunner implements ProcessRunner {
  FakeRunner([this.answers = const <String, ProcResult>{}]);

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
    calls.add(<String>[executable, ...arguments].join(' '));
    return answers[executable] ?? const ProcResult(0, '', '');
  }
}

void main() {
  group('app aliases', () {
    test('known names become something the OS can launch', () {
      expect(AppAliases.resolve(AppAliases.windows, '  Spotify '), 'spotify:');
      expect(AppAliases.resolve(AppAliases.windows, 'VS Code'), 'code');
      expect(AppAliases.resolve(AppAliases.linux, 'chrome'), 'google-chrome');
    });

    test('an unknown name is passed through lower cased', () {
      expect(AppAliases.resolve(AppAliases.windows, 'Blender'), 'blender');
    });

    test('pretty is what the board says out loud', () {
      expect(AppAliases.pretty('vs code'), 'Vs Code');
      expect(AppAliases.pretty('SPOTIFY'), 'Spotify');
    });
  });

  group('media action parsing', () {
    test('accepts what an LLM actually sends', () {
      expect(MediaAction.parse('Play'), MediaAction.play);
      expect(MediaAction.parse('play pause'), MediaAction.playPause);
      expect(MediaAction.parse('volume-up'), MediaAction.volumeUp);
      expect(MediaAction.parse('skip'), MediaAction.next);
    });

    test('nonsense is null, not an exception', () {
      expect(MediaAction.parse('eject the cd'), isNull);
    });
  });

  group('windows openApp', () {
    test('goes through cmd start with an empty title', () async {
      final runner = FakeRunner();
      final tools = WindowsTools(runner: runner);

      expect(await tools.openApp('Spotify'), 'Opened Spotify');
      expect(runner.calls.single, 'cmd /c start  spotify:');
    });

    test('a non-zero exit becomes a NativeToolException', () async {
      final runner = FakeRunner(<String, ProcResult>{
        'cmd': const ProcResult(1, '', 'not found'),
      });

      expect(
        () => WindowsTools(runner: runner).openApp('nope'),
        throwsA(isA<NativeToolException>()),
      );
    });
  });

  group('linux', () {
    test('openApp falls back to xdg-open', () async {
      final runner = FakeRunner(<String, ProcResult>{
        'blender': const ProcResult(127, '', 'no such command'),
      });

      expect(
        await LinuxTools(runner: runner).openApp('blender'),
        'Opened Blender',
      );
      expect(runner.calls, <String>['blender', 'xdg-open blender']);
    });

    test('media maps to playerctl arguments', () async {
      final runner = FakeRunner();
      final tools = LinuxTools(runner: runner);

      await tools.media(MediaAction.playPause);
      await tools.media(MediaAction.volumeDown);

      expect(runner.calls, <String>[
        'playerctl play-pause',
        'playerctl volume 0.1-',
      ]);
    });

    test('stats read /proc, and a missing card is not an error', () async {
      final runner = FakeRunner(<String, ProcResult>{
        'nvidia-smi': const ProcResult.failed('no nvidia-smi'),
      });
      final tools = LinuxTools(runner: runner, procDir: 'test/fixtures/proc');

      final stats = await tools.systemStats();

      expect(stats.memTotalGb, closeTo(31.18, 0.01));
      expect(stats.gpuName, isNull);
    });
  });

  group('file search', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('orion_search');
      File('${root.path}/orion notes.md').writeAsStringSync('hi');
      File('${root.path}/unrelated.txt').writeAsStringSync('hi');
      Directory('${root.path}/nested').createSync();
      File('${root.path}/nested/orion plan.txt').writeAsStringSync('hi');
      Directory('${root.path}/.hidden').createSync();
      File('${root.path}/.hidden/orion secret.txt').writeAsStringSync('hi');
    });

    tearDown(() => root.deleteSync(recursive: true));

    test('matches on part of the name and walks into subfolders', () async {
      final hits = await const FileSearch().search('orion', <Directory>[root]);

      expect(hits.map((h) => h.name), <String>[
        'orion notes.md',
        'orion plan.txt',
      ]);
      expect(hits.first.sizeBytes, 2);
    });

    test('skips dotted folders and stops at maxHits', () async {
      final hits = await const FileSearch(
        maxHits: 1,
      ).search('orion', <Directory>[root]);

      expect(hits, hasLength(1));
    });

    test('an empty query finds nothing at all', () async {
      expect(await const FileSearch().search('  ', <Directory>[root]), isEmpty);
    });
  });

  group('factory', () {
    test('an OS we did not write keeps its tools out of the list', () {
      final tools = nativeToolsFor('android');

      expect(tools, isA<UnsupportedTools>());
      expect(tools.isSupported, isFalse);
      expect(tools.lockPc, throwsA(isA<NativeToolException>()));
    });

    test('windows and linux get their own', () {
      expect(nativeToolsFor('windows').isSupported, isTrue);
      expect(nativeToolsFor('linux').isSupported, isTrue);
    });
  });
}
