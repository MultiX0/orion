import 'dart:io';

/// The Node.js the Windows installer puts next to orion.exe (`node\`), so
/// the PC agent works on a computer that has never had Node: dsh, its MCP
/// servers and every `npx` they start run on it. Installed with Orion and
/// removed with it, never on the user's PATH, and it does not touch a Node
/// they install themselves (windows/installer/orion.iss).
abstract final class BundledNode {
  /// The folder, or null where there is none (a dev build, macOS, Linux):
  /// then whatever Node is on the PATH is used, as before.
  static String? dir({String? executable}) {
    final exe = File(executable ?? Platform.resolvedExecutable);
    final sep = Platform.pathSeparator;
    final d = '${exe.parent.path}${sep}node';
    final node = Platform.isWindows ? 'node.exe' : 'node';
    return File('$d$sep$node').existsSync() ? d : null;
  }

  /// To pass to every process the agent starts: the bundled Node first on
  /// the PATH. Empty without one. Merged over the parent environment.
  static Map<String, String> environment({
    String? executable,
    Map<String, String>? parent,
  }) {
    final d = dir(executable: executable);
    if (d == null) return const <String, String>{};
    final env = parent ?? Platform.environment;
    final path = env['PATH'] ?? env['Path'] ?? '';
    return <String, String>{
      'PATH': path.isEmpty ? d : '$d${Platform.isWindows ? ';' : ':'}$path',
      // A first run on a new PC would otherwise stop to ask about updates.
      'NPM_CONFIG_UPDATE_NOTIFIER': 'false',
      'NPM_CONFIG_FUND': 'false',
    };
  }
}
