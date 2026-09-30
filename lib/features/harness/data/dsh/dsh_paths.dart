import 'dart:io';

/// Where the harness keeps its own things. Nothing here is ever the user's
/// home directory: dsh gets `~/Orion/agent` and no more, per docs/HARNESS.md.
class DshPaths {
  const DshPaths(this.root);

  /// `~/Orion`, or `%USERPROFILE%\Orion` on Windows.
  factory DshPaths.underUserHome({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
    return DshPaths('$home${Platform.pathSeparator}Orion');
  }

  final String root;

  String get sandbox => _join(root, 'agent');

  /// Our own DSH_HOME, so we never write into the user's `~/.dsh`.
  String get dshHome => _join(sandbox, '.dsh');

  String get settingsFile => _join(dshHome, 'settings.yaml');

  String get envFile => _join(dshHome, '.env');

  String get logsDir => _join(root, 'logs');

  String get toolLogFile => _join(logsDir, 'tools.jsonl');

  Future<void> ensureDirectories() async {
    for (final dir in <String>[sandbox, dshHome, logsDir]) {
      await Directory(dir).create(recursive: true);
    }
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}
