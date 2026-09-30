import 'dart:io';

import 'package:orion/features/harness/data/native_tools/native_tools_factory.dart';
import 'package:orion/features/harness/data/native_tools/win_user32.dart';
import 'package:orion/features/harness/domain/media_action.dart';
import 'package:orion/features/harness/domain/native_tools.dart';

/// Fires each native tool once and prints what happened, so the results can
/// be written down instead of guessed at. Run it with:
///   dart run tool/native_tools_check.dart [open|stats|shot|media|find|lock]
/// With no argument it runs everything except lock_pc, which locks the PC.
Future<void> main(List<String> args) async {
  final tools = nativeToolsFor(Platform.operatingSystem);
  final only = args.isEmpty ? <String>[] : args;
  bool want(String name) => only.isEmpty || only.contains(name);

  _line(
    'platform',
    '${Platform.operatingSystem}, supported ${tools.isSupported}',
  );

  if (want('open')) {
    await _try('open_app spotify', () => tools.openApp('spotify'));
    await _try('open_app notepad', () => tools.openApp('notepad'));
  }
  // open=<name> for anything else, including apps only the Start Menu knows.
  for (final arg in only.where((a) => a.startsWith('open='))) {
    final name = arg.substring(5);
    await _try('open_app $name', () => tools.openApp(name));
  }
  if (want('stats')) {
    await _try('system_stats', () async => (await tools.systemStats()).spoken);
  }
  if (want('shot')) {
    await _try('screenshot', () async {
      final png = await tools.screenshot();
      return '${png.length} bytes, header ${png.take(4).toList()}';
    });
  }
  if (want('media')) {
    await _try(
      'media play_pause',
      () async => tools.media(MediaAction.playPause).then((_) => 'sent'),
    );
  }
  if (want('find')) {
    await _try('search_files', () async {
      final hits = await tools.searchFiles('orion');
      return hits.isEmpty
          ? 'nothing matched'
          : hits.map((h) => h.path).join('\n            ');
    });
  }
  if (Platform.isWindows) {
    final user32 = WinUser32.open();
    _line(
      'lock_pc binding',
      user32 == null ? 'user32 did not load' : 'LockWorkStation resolves',
    );
  }
  // Last, on purpose, and only when asked for by name.
  if (only.contains('lock')) {
    await _try('lock_pc', () async {
      await tools.lockPc();
      return 'locked';
    });
  }
}

Future<void> _try(String label, Future<String> Function() run) async {
  final started = DateTime.now();
  try {
    final result = await run();
    _line(label, '$result  (${_ms(started)} ms)');
  } on NativeToolException catch (e) {
    _line(label, 'FAILED ${e.message}  (${_ms(started)} ms)');
  }
}

int _ms(DateTime from) => DateTime.now().difference(from).inMilliseconds;

void _line(String label, String value) =>
    stdout.writeln('${label.padRight(18)} $value');
