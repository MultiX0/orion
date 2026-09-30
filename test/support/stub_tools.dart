import 'dart:typed_data';

import 'package:orion/features/harness/domain/file_hit.dart';
import 'package:orion/features/harness/domain/media_action.dart';
import 'package:orion/features/harness/domain/native_tools.dart';
import 'package:orion/features/harness/domain/system_stats.dart';

/// NativeTools that record instead of touching the OS.
class StubTools implements NativeTools {
  final calls = <String>[];
  bool lockFails = false;

  @override
  bool get isSupported => true;

  @override
  Future<String> openApp(String name) async {
    calls.add('openApp:$name');
    return 'Opened $name';
  }

  @override
  Future<void> lockPc() async {
    calls.add('lockPc');
    if (lockFails) throw const NativeToolException('The screen said no');
  }

  @override
  Future<SystemStats> systemStats() async => const SystemStats(cpuPct: 12);

  @override
  Future<Uint8List> screenshot() async => Uint8List.fromList(<int>[1, 2, 3]);

  @override
  Future<List<FileHit>> searchFiles(String query) async => <FileHit>[
    const FileHit(name: 'notes.md', path: '/tmp/notes.md'),
  ];

  @override
  Future<void> media(MediaAction action) async => calls.add('media:$action');
}
