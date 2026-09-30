import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app.dart';
import 'core/platform/platform_info.dart';
import 'core/storage/legacy_data_move.dart';
import 'core/theme/tokens.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before anything opens the settings or the keychain.
  await moveLegacyAppData();
  if (PlatformInfo.detect().isDesktop) await _setUpWindow();
  runApp(const ProviderScope(child: OrionApp()));
}

Future<void> _setUpWindow() async {
  await windowManager.ensureInitialized();
  const options = WindowOptions(
    size: Size(1280, 800),
    minimumSize: Size(1100, 720),
    center: true,
    title: 'Orion',
    backgroundColor: OrionColors.bgPrimary,
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.show();
    await windowManager.focus();
  });
}
