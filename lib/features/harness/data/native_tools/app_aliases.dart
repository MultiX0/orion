/// Names people say, mapped to something the OS can launch. Anything not in
/// here is handed to the shell as typed, which is what `start` and
/// `xdg-open` are for.
abstract final class AppAliases {
  static const windows = <String, String>{
    'spotify': 'spotify:',
    'chrome': 'chrome',
    'edge': 'msedge',
    'firefox': 'firefox',
    'vscode': 'code',
    'vs code': 'code',
    'visual studio code': 'code',
    'discord': 'discord:',
    'steam': 'steam:',
    'explorer': 'explorer',
    'files': 'explorer',
    'terminal': 'wt',
    'notepad': 'notepad',
    'calculator': 'calc',
    'settings': 'ms-settings:',
    'task manager': 'taskmgr',
  };

  static const linux = <String, String>{
    'spotify': 'spotify',
    'chrome': 'google-chrome',
    'firefox': 'firefox',
    'vscode': 'code',
    'vs code': 'code',
    'visual studio code': 'code',
    'discord': 'discord',
    'steam': 'steam',
    'explorer': 'xdg-open',
    'files': 'nautilus',
    'terminal': 'x-terminal-emulator',
  };

  /// Lower-cases and trims first, so "Open Spotify " still lands.
  static String resolve(Map<String, String> table, String spoken) {
    final key = spoken.trim().toLowerCase();
    return table[key] ?? key;
  }

  /// "spotify" -> "Spotify", for the line the board reads out.
  static String pretty(String spoken) {
    final words = spoken.trim().split(RegExp(r'\s+'));
    return words
        .map(
          (w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }
}
