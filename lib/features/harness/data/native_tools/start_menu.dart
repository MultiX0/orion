import 'dart:io';

/// Start Menu shortcuts, so "open spotify" works whether or not the app is
/// on the PATH. Both the user's folder and the machine's are searched.
class StartMenu {
  const StartMenu({this.maxDepth = 3});

  final int maxDepth;

  static List<Directory> roots({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    const tail = r'\Microsoft\Windows\Start Menu\Programs';
    return <Directory>[
      if (env['APPDATA'] != null) Directory('${env['APPDATA']}$tail'),
      if (env['ProgramData'] != null) Directory('${env['ProgramData']}$tail'),
    ].where((d) => d.existsSync()).toList();
  }

  /// The best shortcut for a spoken name: an exact stem beats a prefix,
  /// a prefix beats a name that merely contains the words.
  static String? bestMatch(List<String> shortcuts, String spoken) {
    final wanted = spoken.trim().toLowerCase();
    if (wanted.isEmpty) return null;
    String? prefix;
    String? contains;
    for (final path in shortcuts) {
      final stem = _stem(path);
      if (stem == wanted) return path;
      if (stem.startsWith(wanted)) {
        prefix ??= path;
        continue;
      }
      if (stem.contains(wanted)) contains ??= path;
    }
    return prefix ?? contains;
  }

  Future<String?> find(String spoken) async {
    final shortcuts = <String>[];
    for (final root in roots()) {
      await _collect(root, 0, shortcuts);
    }
    return bestMatch(shortcuts, spoken);
  }

  Future<void> _collect(Directory dir, int depth, List<String> out) async {
    if (depth > maxDepth || out.length > 2000) return;
    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return; // A folder we cannot read is not a reason to stop.
    }
    for (final entry in entries) {
      if (entry is Directory) {
        await _collect(entry, depth + 1, out);
      } else if (entry is File && entry.path.toLowerCase().endsWith('.lnk')) {
        out.add(entry.path);
      }
    }
  }

  static String _stem(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).toLowerCase();
  }
}
