import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import '../../../core/result.dart';

/// Where a saved frame lands: `~/Orion/snapshots` on a desktop, next to the
/// logs and the agent folder, and the app documents folder on a phone, which
/// is the only place an app may write there.
class SnapshotStore {
  const SnapshotStore({this.folder});

  /// Injected in tests, so nothing touches a real home directory.
  final Future<Directory> Function()? folder;

  Future<Result<String>> write(Uint8List bytes, {DateTime? at}) async {
    if (bytes.isEmpty) {
      return const Err(StorageFailure('That frame was empty'));
    }
    try {
      final dir = await (folder?.call() ?? _defaultFolder());
      await dir.create(recursive: true);
      final file = File(
        '${dir.path}${Platform.pathSeparator}'
        '${fileName(at ?? DateTime.now())}',
      );
      await file.writeAsBytes(bytes, flush: true);
      return Ok(file.path);
    } on FileSystemException catch (e) {
      return Err(StorageFailure('Could not save the snapshot: ${e.message}'));
    } on MissingPlatformDirectoryException {
      return const Err(StorageFailure('This device has nowhere to save it'));
    }
  }

  /// Sorts by name, which is the same as by time.
  static String fileName(DateTime at) {
    final t = at.toLocal();
    final stamp =
        '${t.year}${_two(t.month)}${_two(t.day)}-'
        '${_two(t.hour)}${_two(t.minute)}${_two(t.second)}';
    return 'orion-$stamp-${t.millisecond.toString().padLeft(3, '0')}.jpg';
  }

  Future<Directory> _defaultFolder() async {
    if (Platform.isAndroid || Platform.isIOS) {
      final docs = await getApplicationDocumentsDirectory();
      return Directory('${docs.path}${Platform.pathSeparator}snapshots');
    }
    final env = Platform.environment;
    final home = env['USERPROFILE'] ?? env['HOME'] ?? Directory.current.path;
    final sep = Platform.pathSeparator;
    return Directory('$home${sep}Orion${sep}snapshots');
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}
