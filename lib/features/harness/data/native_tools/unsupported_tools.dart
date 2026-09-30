import 'dart:typed_data';

import '../../domain/file_hit.dart';
import '../../domain/media_action.dart';
import '../../domain/native_tools.dart';
import '../../domain/system_stats.dart';

/// What a phone, or an OS we have not written yet, gets. Every method throws,
/// but nothing calls them: `isSupported` keeps the tools out of GET /tools.
class UnsupportedTools implements NativeTools {
  const UnsupportedTools();

  @override
  bool get isSupported => false;

  Never _no() =>
      throw const NativeToolException('This PC cannot run native tools');

  @override
  Future<String> openApp(String name) async => _no();

  @override
  Future<void> lockPc() async => _no();

  @override
  Future<SystemStats> systemStats() async => _no();

  @override
  Future<Uint8List> screenshot() async => _no();

  @override
  Future<List<FileHit>> searchFiles(String query) async => _no();

  @override
  Future<void> media(MediaAction action) async => _no();
}
