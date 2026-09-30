import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/storage_providers.dart';
import '../core/theme/theme.dart';
import '../core/theme/tokens.dart';
import '../features/device/data/device_state_notifier.dart';
import '../features/harness/data/harness_providers.dart';
import '../features/settings/data/time_zone_sync.dart';
import 'router.dart';

class OrionApp extends ConsumerWidget {
  const OrionApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Keeps the board connection alive from app start, without rebuilding here.
    ref.listen(deviceStateProvider, (_, _) {});
    // PC control too. Built lazily, the harness would wait for a screen to
    // ask for it, and the PC brain would stay down after a restart until
    // someone opened Harness or Settings.
    ref.listen(harnessRepositoryProvider, (_, _) {});
    // The board's clock follows this device's time zone while on automatic.
    ref.listen(timeZoneSyncProvider, (_, _) {});
    final theme = buildOrionTheme();
    final settings = ref.watch(appSettingsProvider);
    if (settings is! AsyncData) {
      // Settings load in a few ms. A plain dark surface avoids a flash.
      return MaterialApp(
        theme: theme,
        debugShowCheckedModeBanner: false,
        home: const ColoredBox(color: OrionColors.bgPrimary),
      );
    }
    return MaterialApp.router(
      title: 'Orion',
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
