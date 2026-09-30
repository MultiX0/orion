import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// On Windows the app keeps its settings and its keychain file in a folder
/// named after the company and product in the exe's version info. Those
/// became "MultiX0" and "Orion" in 1.0.0, so an update would otherwise open
/// with an empty folder: no pairing, no keys, PC control off. This
/// carries the old folder's two files across once, before anything reads
/// them. A folder that already has settings is left as it is.
Future<void> moveLegacyAppData() async {
  if (!Platform.isWindows) return;
  try {
    final appData = Platform.environment['APPDATA'];
    if (appData == null) return;
    final old = Directory('$appData\\dev.orion\\orion');
    final now = await getApplicationSupportDirectory();
    if (!old.existsSync() || old.path == now.path) return;
    const files = ['shared_preferences.json', 'flutter_secure_storage.dat'];
    if (File('${now.path}\\${files.first}').existsSync()) return;
    now.createSync(recursive: true);
    for (final name in files) {
      final from = File('${old.path}\\$name');
      if (from.existsSync()) from.copySync('${now.path}\\$name');
    }
  } on Object {
    // Moving is a help: without it the app starts fresh, as on a new PC.
  }
}
