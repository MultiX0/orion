import 'dart:typed_data';

import 'file_hit.dart';
import 'media_action.dart';
import 'system_stats.dart';

/// The fast, safe actions the desktop can take without an agent.
/// One implementation per OS, chosen once at startup.
abstract class NativeTools {
  /// True when this OS is actually supported. False keeps every native tool
  /// out of GET /tools instead of failing a call the LLM already made.
  bool get isSupported;

  /// Returns a line the board can say, for example "Opened Spotify".
  Future<String> openApp(String name);

  Future<void> lockPc();

  Future<SystemStats> systemStats();

  /// PNG bytes. The caller turns them into a description.
  Future<Uint8List> screenshot();

  Future<List<FileHit>> searchFiles(String query);

  Future<void> media(MediaAction action);
}

/// Thrown by a native tool when the OS said no. The tool server maps it to
/// { "status": "error" } so the board can tell the user.
class NativeToolException implements Exception {
  const NativeToolException(this.message);
  final String message;

  @override
  String toString() => message;
}
