import 'dart:io';

import '../../domain/file_hit.dart';
import 'process_runner.dart';

/// The Windows Search index through the Search.CollatorDSO OLE DB provider.
/// An indexed drive answers in well under a second, which a folder walk
/// never does. Nothing back means the index is off, and the caller walks.
class WindowsSearchIndex {
  const WindowsSearchIndex({
    this.runner = const SystemProcessRunner(),
    this.maxHits = 10,
    this.timeout = const Duration(seconds: 6),
  });

  final ProcessRunner runner;
  final int maxHits;
  final Duration timeout;

  /// The query comes from the board's LLM, so everything that could close a
  /// SQL string or a PowerShell one is dropped before it goes near either.
  static String sanitize(String query) =>
      query.trim().replaceAll(RegExp(r'[^A-Za-z0-9 ._-]'), '');

  static String sqlFor(String needle, List<String> roots, {int top = 10}) {
    final scopes = roots.map((r) => "SCOPE='file:$r'").join(' OR ');
    return 'SELECT TOP $top System.ItemPathDisplay FROM SYSTEMINDEX '
        "WHERE System.FileName LIKE '%$needle%' "
        "AND System.ItemType <> 'Directory'"
        '${scopes.isEmpty ? '' : ' AND ($scopes)'}';
  }

  /// One absolute path per line. PowerShell adds blank lines and, when the
  /// provider is missing, an error block; neither looks like a path.
  static List<String> parsePaths(String stdout) => stdout
      .split('\n')
      .map((line) => line.trim())
      .where((line) => RegExp(r'^[A-Za-z]:\\').hasMatch(line))
      .toList();

  static String scriptFor(String sql) {
    final escaped = sql.replaceAll('"', '""').replaceAll(r'$', '`\$');
    return r'$c = New-Object -ComObject ADODB.Connection; '
        r'$c.Open("Provider=Search.CollatorDSO;'
        'Extended Properties=\'Application=Windows\'"); '
        '\$r = \$c.Execute("$escaped"); '
        r'while (-not $r.EOF) { $r.Fields.Item(0).Value; $r.MoveNext() }; '
        r'$c.Close()';
  }

  /// Empty when the index is off, the provider is missing or nothing matched.
  Future<List<FileHit>> search(String query, List<String> roots) async {
    final needle = sanitize(query);
    if (needle.isEmpty) return const <FileHit>[];
    final result = await runner.run('powershell', <String>[
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      scriptFor(sqlFor(needle, roots, top: maxHits)),
    ], timeout: timeout);
    if (!result.ok) return const <FileHit>[];
    final hits = <FileHit>[];
    for (final path in parsePaths(result.stdout).take(maxHits)) {
      hits.add(await _hit(path));
    }
    return hits;
  }

  Future<FileHit> _hit(String path) async {
    final name = path.split(RegExp(r'[\\/]')).last;
    try {
      final stat = await File(path).stat();
      return FileHit(
        name: name,
        path: path,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
      );
    } on FileSystemException {
      return FileHit(name: name, path: path);
    }
  }
}
