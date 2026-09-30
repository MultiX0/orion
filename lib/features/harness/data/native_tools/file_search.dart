import 'dart:io';

import '../../domain/file_hit.dart';

/// A name search over Documents, Downloads and Desktop. Plain Dart, because
/// every OS indexer wants a different dance and none of them are quick to
/// start. Bounded by depth, hit count and a wall clock, so a network drive
/// mounted under Documents cannot hang a turn.
class FileSearch {
  const FileSearch({
    this.maxDepth = 4,
    this.maxHits = 10,
    this.budget = const Duration(seconds: 6),
  });

  final int maxDepth;
  final int maxHits;
  final Duration budget;

  /// The three folders docs/HARNESS.md allows. Nothing else is searched.
  static List<Directory> defaultRoots({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'];
    if (home == null || home.isEmpty) return const <Directory>[];
    return <Directory>[
      Directory('$home${Platform.pathSeparator}Documents'),
      Directory('$home${Platform.pathSeparator}Downloads'),
      Directory('$home${Platform.pathSeparator}Desktop'),
    ].where((d) => d.existsSync()).toList();
  }

  Future<List<FileHit>> search(String query, List<Directory> roots) async {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const <FileHit>[];
    final deadline = DateTime.now().add(budget);
    final hits = <FileHit>[];
    for (final root in roots) {
      await _walk(root, needle, 0, hits, deadline);
      if (hits.length >= maxHits) break;
    }
    return hits;
  }

  Future<void> _walk(
    Directory dir,
    String needle,
    int depth,
    List<FileHit> hits,
    DateTime deadline,
  ) async {
    if (depth > maxDepth ||
        hits.length >= maxHits ||
        DateTime.now().isAfter(deadline)) {
      return;
    }
    final List<FileSystemEntity> entries;
    try {
      entries = await dir.list(followLinks: false).toList();
    } on FileSystemException {
      return; // Permission denied on a folder is normal, keep going.
    }
    final subdirs = <Directory>[];
    for (final entry in entries) {
      final name = entry.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      if (name == null || name.startsWith('.')) continue;
      if (entry is Directory) {
        subdirs.add(entry);
        continue;
      }
      if (entry is! File || !name.toLowerCase().contains(needle)) continue;
      hits.add(await _hit(entry, name));
      if (hits.length >= maxHits) return;
    }
    for (final sub in subdirs) {
      await _walk(sub, needle, depth + 1, hits, deadline);
      if (hits.length >= maxHits) return;
    }
  }

  Future<FileHit> _hit(File file, String name) async {
    try {
      final stat = await file.stat();
      return FileHit(
        name: name,
        path: file.path,
        sizeBytes: stat.size,
        modifiedAt: stat.modified,
      );
    } on FileSystemException {
      return FileHit(name: name, path: file.path);
    }
  }
}
