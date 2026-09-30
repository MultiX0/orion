import 'dart:io';
import 'dart:typed_data';

import '../../domain/file_hit.dart';
import '../../domain/media_action.dart';
import '../../domain/native_tools.dart';
import '../../domain/system_stats.dart';
import 'app_aliases.dart';
import 'file_search.dart';
import 'process_runner.dart';
import 'stats_parsers.dart';

/// Linux. Stats come from /proc, which is faster and more honest than any
/// tool we could shell out to. Screenshots try grim first, for Wayland.
class LinuxTools implements NativeTools {
  LinuxTools({
    this.runner = const SystemProcessRunner(),
    this.search = const FileSearch(),
    this.procDir = '/proc',
  });

  final ProcessRunner runner;
  final FileSearch search;
  final String procDir;

  @override
  bool get isSupported => true;

  @override
  Future<String> openApp(String name) async {
    final target = AppAliases.resolve(AppAliases.linux, name);
    var result = await runner.run(target, const <String>[]);
    if (!result.ok) {
      result = await runner.run('xdg-open', <String>[target]);
    }
    if (!result.ok) {
      throw NativeToolException('Could not open ${AppAliases.pretty(name)}');
    }
    return 'Opened ${AppAliases.pretty(name)}';
  }

  @override
  Future<void> lockPc() async {
    for (final cmd in const <(String, List<String>)>[
      ('loginctl', <String>['lock-session']),
      ('xdg-screensaver', <String>['lock']),
    ]) {
      if ((await runner.run(cmd.$1, cmd.$2)).ok) return;
    }
    throw const NativeToolException('Nothing on this desktop would lock it');
  }

  @override
  Future<SystemStats> systemStats() async {
    var stats = StatsParsers.linuxMemory(await _read('$procDir/meminfo'));
    final first = await _read('$procDir/stat');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    final second = await _read('$procDir/stat');
    stats = stats.copyWith(
      cpuPct: StatsParsers.linuxCpuPct(first, second),
      cpuTempC: StatsParsers.linuxTempC(
        await _read('/sys/class/thermal/thermal_zone0/temp'),
      ),
    );
    final gpu = await runner.run('nvidia-smi', <String>[
      '--query-gpu=name,utilization.gpu,temperature.gpu',
      '--format=csv,noheader,nounits',
    ], timeout: const Duration(seconds: 5));
    if (gpu.ok) {
      final card = StatsParsers.nvidia(gpu.stdout);
      stats = stats.copyWith(
        gpuName: card.gpuName,
        gpuPct: card.gpuPct,
        gpuTempC: card.gpuTempC,
      );
    }
    return stats;
  }

  @override
  Future<Uint8List> screenshot() async {
    final path =
        '${Directory.systemTemp.path}/orion_shot_'
        '${DateTime.now().millisecondsSinceEpoch}.png';
    for (final cmd in <(String, List<String>)>[
      ('grim', <String>[path]),
      ('scrot', <String>['-o', path]),
      ('import', <String>['-window', 'root', path]),
    ]) {
      final result = await runner.run(
        cmd.$1,
        cmd.$2,
        timeout: const Duration(seconds: 20),
      );
      final file = File(path);
      if (result.ok && file.existsSync()) {
        final bytes = await file.readAsBytes();
        await file.delete();
        return bytes;
      }
    }
    throw const NativeToolException(
      'No screenshot tool found. Install grim or scrot.',
    );
  }

  @override
  Future<List<FileHit>> searchFiles(String query) =>
      search.search(query, FileSearch.defaultRoots());

  @override
  Future<void> media(MediaAction action) async {
    final command = switch (action) {
      MediaAction.play => 'play',
      MediaAction.pause => 'pause',
      MediaAction.playPause => 'play-pause',
      MediaAction.next => 'next',
      MediaAction.previous => 'previous',
      MediaAction.volumeUp => 'volume',
      MediaAction.volumeDown => 'volume',
      MediaAction.mute => 'volume',
    };
    final args = switch (action) {
      MediaAction.volumeUp => <String>['volume', '0.1+'],
      MediaAction.volumeDown => <String>['volume', '0.1-'],
      MediaAction.mute => <String>['volume', '0'],
      _ => <String>[command],
    };
    final result = await runner.run('playerctl', args);
    if (!result.ok) {
      throw const NativeToolException(
        'playerctl is not installed, so media keys do nothing',
      );
    }
  }

  Future<String> _read(String path) async {
    try {
      return await File(path).readAsString();
    } on FileSystemException {
      return '';
    }
  }
}
