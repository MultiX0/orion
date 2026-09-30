import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/harness/data/native_tools/process_runner.dart';
import 'package:orion/features/harness/data/native_tools/start_menu.dart';
import 'package:orion/features/harness/data/native_tools/windows_search.dart';
import 'package:orion/features/harness/data/native_tools/windows_tools.dart';
import 'package:orion/features/harness/domain/native_tools.dart';

/// Answers whatever the test tells it to, and remembers what was asked.
class _ScriptedRunner implements ProcessRunner {
  _ScriptedRunner(this.reply);

  final ProcResult Function(String exe, List<String> args) reply;
  final commands = <String>[];

  @override
  Future<ProcResult> run(
    String executable,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    String? workingDirectory,
    Map<String, String>? environment,
    bool shell = false,
  }) async {
    commands.add('$executable ${arguments.join(' ')}');
    return reply(executable, arguments);
  }
}

void main() {
  group('the Search index', () {
    test('real stdout becomes paths, noise does not', () {
      final output = File(
        'test/fixtures/search_index_stdout.txt',
      ).readAsStringSync();
      final paths = WindowsSearchIndex.parsePaths(output);
      expect(paths, hasLength(5));
      expect(paths.first, endsWith('.md'));
      expect(
        WindowsSearchIndex.parsePaths(
          'New-Object : Retrieving the COM class factory failed',
        ),
        isEmpty,
      );
    });

    test('the query is scoped to the three folders', () {
      final sql = WindowsSearchIndex.sqlFor('notes', <String>[
        r'C:\Users\me\Documents',
        r'C:\Users\me\Desktop',
      ], top: 10);
      expect(sql, contains('SELECT TOP 10 System.ItemPathDisplay'));
      expect(sql, contains("System.FileName LIKE '%notes%'"));
      expect(sql, contains(r"SCOPE='file:C:\Users\me\Documents'"));
      expect(sql, contains("System.ItemType <> 'Directory'"));
    });

    test('a query from the board cannot close the SQL string', () {
      final needle = WindowsSearchIndex.sanitize("notes' OR '1'='1");
      expect(needle, isNot(contains("'")));
      expect(
        WindowsSearchIndex.sqlFor(needle, const <String>[]),
        isNot(contains("''")),
      );
      expect(WindowsSearchIndex.sanitize(r'a$b`c"d'), 'abcd');
    });

    test('an index that is off gives nothing, never a throw', () async {
      final runner = _ScriptedRunner(
        (_, _) => const ProcResult.failed('provider missing'),
      );
      final hits = await WindowsSearchIndex(
        runner: runner,
      ).search('notes', const <String>[]);
      expect(hits, isEmpty);
    });
  });

  group('Start Menu shortcuts', () {
    final shortcuts = File(
      'test/fixtures/start_menu_lnk.txt',
    ).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

    test('an exact name wins', () {
      expect(StartMenu.bestMatch(shortcuts, 'slack'), endsWith('Slack.lnk'));
      expect(
        StartMenu.bestMatch(shortcuts, 'Notepad '),
        endsWith('Notepad.lnk'),
      );
    });

    test('a prefix beats a name that only contains the words', () {
      // "Steam.lnk" and "Uninstall Steam.lnk" both match; uninstall must not.
      expect(
        StartMenu.bestMatch(shortcuts, 'steam'),
        endsWith(r'Steam\Steam.lnk'),
      );
      expect(
        StartMenu.bestMatch(shortcuts, 'blender'),
        contains('Blender 4.2'),
      );
    });

    test('nothing close enough is null, not a guess', () {
      expect(StartMenu.bestMatch(shortcuts, 'photoshop'), isNull);
      expect(StartMenu.bestMatch(shortcuts, ''), isNull);
    });
  });

  group('open_app', () {
    test('a protocol alias goes straight to start', () async {
      final runner = _ScriptedRunner((_, _) => const ProcResult(0, '', ''));
      final tools = WindowsTools(runner: runner, user32: null);
      expect(await tools.openApp('spotify'), 'Opened Spotify');
      expect(runner.commands.single, 'cmd /c start  spotify:');
    });

    test('a name on the PATH is checked with where first', () async {
      final runner = _ScriptedRunner((_, _) => const ProcResult(0, '', ''));
      final tools = WindowsTools(runner: runner, user32: null);
      await tools.openApp('notepad');
      expect(runner.commands.first, 'cmd /c where notepad');
      expect(runner.commands.last, 'cmd /c start  notepad');
    });

    test('a name Windows does not know never reaches start', () async {
      // Handing it to start would pop the "how do you want to open this"
      // dialog and block until a person clicks it.
      final runner = _ScriptedRunner(
        (_, _) => const ProcResult.failed('not found'),
      );
      final tools = WindowsTools(runner: runner, user32: null);
      await expectLater(
        tools.openApp('nosuchapp'),
        throwsA(isA<NativeToolException>()),
      );
      expect(runner.commands.where((c) => c.contains('start')), isEmpty);
    });
  });

  test('a child that never exits is killed, not waited on', () async {
    const runner = SystemProcessRunner();
    final started = DateTime.now();
    final result = await runner.run(
      Platform.isWindows ? 'cmd' : 'sh',
      Platform.isWindows
          ? <String>['/c', 'pause']
          : <String>['-c', 'read line'],
      timeout: const Duration(milliseconds: 400),
    );
    expect(result.ok, isFalse);
    expect(result.stderr, contains('timed out'));
    expect(DateTime.now().difference(started).inSeconds, lessThan(5));
  });
}
