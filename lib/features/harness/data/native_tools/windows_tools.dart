import 'dart:io';
import 'dart:typed_data';

import '../../domain/file_hit.dart';
import '../../domain/media_action.dart';
import '../../domain/native_tools.dart';
import '../../domain/system_stats.dart';
import 'app_aliases.dart';
import 'file_search.dart';
import 'process_runner.dart';
import 'start_menu.dart';
import 'stats_parsers.dart';
import 'win_user32.dart';
import 'windows_search.dart';

/// Windows. Launching goes through `cmd /c start`, which handles both
/// executables and protocol handlers like `spotify:`. Stats come from one
/// PowerShell call plus nvidia-smi when there is a card.
class WindowsTools implements NativeTools {
  WindowsTools({
    this.runner = const SystemProcessRunner(),
    this.search = const FileSearch(),
    this.startMenu = const StartMenu(),
    WindowsSearchIndex? index,
    WinUser32? user32,
  }) : index = index ?? WindowsSearchIndex(runner: runner),
       _user32 = user32 ?? WinUser32.open();

  final ProcessRunner runner;
  final FileSearch search;
  final StartMenu startMenu;

  /// The Search index first. The walk in [search] is the fallback.
  final WindowsSearchIndex index;

  final WinUser32? _user32;

  static const _statsScript =
      r'$os = Get-CimInstance Win32_OperatingSystem; '
      r'$cpu = (Get-CimInstance Win32_Processor | '
      r'Measure-Object -Property LoadPercentage -Average).Average; '
      r'[pscustomobject]@{ Cpu = $cpu; FreeKb = $os.FreePhysicalMemory; '
      r'TotalKb = $os.TotalVisibleMemorySize } | ConvertTo-Json -Compress';

  @override
  bool get isSupported => true;

  @override
  Future<String> openApp(String name) async {
    final target = AppAliases.resolve(AppAliases.windows, name);
    // Handing a word Windows does not know to start pops the "How do you
    // want to open this file" dialog and blocks until someone clicks it, so
    // nothing is launched that where or the Start Menu cannot place first.
    if (_isProtocol(target) || await _onPath(target)) {
      if (await _start(target)) return 'Opened ${AppAliases.pretty(name)}';
    }
    final shortcut = await startMenu.find(name);
    if (shortcut != null && await _start(shortcut)) {
      return 'Opened ${AppAliases.pretty(name)}';
    }
    throw NativeToolException(
      'I could not find ${AppAliases.pretty(name)} on this PC',
    );
  }

  static bool _isProtocol(String target) =>
      target.endsWith(':') || target.contains('://');

  Future<bool> _onPath(String target) async {
    if (target.contains('\\') || target.contains('/')) return true;
    final result = await runner.run('cmd', <String>[
      '/c',
      'where',
      target,
    ], timeout: const Duration(seconds: 5));
    return result.ok;
  }

  /// The empty string is start's title argument. Without it a quoted target
  /// becomes the window title and nothing launches.
  Future<bool> _start(String target) async {
    final result = await runner.run('cmd', <String>['/c', 'start', '', target]);
    return result.ok;
  }

  @override
  Future<void> lockPc() async {
    final user32 = _user32;
    if (user32 == null || !user32.lockWorkStation()) {
      throw const NativeToolException('Windows would not lock the session');
    }
  }

  @override
  Future<SystemStats> systemStats() async {
    final host = await _powershell(_statsScript);
    var stats = StatsParsers.windows(host.stdout);
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
        '${Directory.systemTemp.path}\\orion_shot_'
        '${DateTime.now().millisecondsSinceEpoch}.png';
    final script =
        'Add-Type -AssemblyName System.Windows.Forms,System.Drawing; '
        r'$b = [System.Windows.Forms.SystemInformation]::VirtualScreen; '
        r'$bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height; '
        r'$g = [System.Drawing.Graphics]::FromImage($bmp); '
        r'$g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size); '
        "\$bmp.Save('$path', "
        '[System.Drawing.Imaging.ImageFormat]::Png)';
    final result = await _powershell(
      script,
      timeout: const Duration(seconds: 20),
    );
    final file = File(path);
    if (!result.ok || !file.existsSync()) {
      throw const NativeToolException('Could not capture the screen');
    }
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  @override
  Future<List<FileHit>> searchFiles(String query) async {
    final roots = FileSearch.defaultRoots();
    final indexed = await index.search(
      query,
      roots.map((d) => d.path).toList(),
    );
    if (indexed.isNotEmpty) return indexed;
    return search.search(query, roots);
  }

  @override
  Future<void> media(MediaAction action) async {
    final user32 = _user32;
    if (user32 == null) {
      throw const NativeToolException('No access to the media keys');
    }
    user32.tapKey(switch (action) {
      MediaAction.play ||
      MediaAction.pause ||
      MediaAction.playPause => WinUser32.vkMediaPlayPause,
      MediaAction.next => WinUser32.vkMediaNextTrack,
      MediaAction.previous => WinUser32.vkMediaPrevTrack,
      MediaAction.volumeUp => WinUser32.vkVolumeUp,
      MediaAction.volumeDown => WinUser32.vkVolumeDown,
      MediaAction.mute => WinUser32.vkVolumeMute,
    });
  }

  Future<ProcResult> _powershell(
    String script, {
    Duration timeout = const Duration(seconds: 10),
  }) => runner.run('powershell', <String>[
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    script,
  ], timeout: timeout);
}
