import 'dart:io';

/// Where the harness keeps its own things: dsh's home is `~/Orion/agent/.dsh`,
/// never the user's own `~/.dsh`. With desktop control the agent works in the
/// user's home (docs/HARNESS.md, "The PC agent").
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

  String get envFile => _join(dshHome, '.env');

  /// A dsh profile's folder: its patch layer and its installed plugins.
  String profileDir(String profile) =>
      _join(_join(dshHome, 'profiles'), profile);

  String profilePatch(String profile) =>
      _join(profileDir(profile), 'cordis.patch.yml');

  /// Where the agent works with desktop control: the user's own home, since
  /// it downloads and opens their files. USERPROFILE on Windows.
  static String downloads({Map<String, String>? environment}) =>
      _join(userHome(environment: environment), 'Downloads');

  static String userHome({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    return env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
  }

  String get logsDir => _join(root, 'logs');

  String get toolLogFile => _join(logsDir, 'tools.jsonl');

  Future<void> ensureDirectories() async {
    for (final dir in <String>[sandbox, dshHome, logsDir]) {
      await Directory(dir).create(recursive: true);
    }
  }

  static String _join(String a, String b) => '$a${Platform.pathSeparator}$b';
}
