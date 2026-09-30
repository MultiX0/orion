import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/platform/platform_info.dart';
import '../../core/theme/tokens.dart';
import 'desktop_rail.dart';
import 'mobile_nav_bar.dart';

/// Scaffold chrome. The only widget that reads PlatformInfo.isMobile for
/// layout: bottom bar on phones, left rail on desktop, same routes.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final platform = ref.watch(platformInfoProvider);
    final location = GoRouterState.of(context).uri.path;
    if (platform.isMobile) {
      return Scaffold(
        backgroundColor: OrionColors.bgPrimary,
        extendBody: true,
        body: child,
        bottomNavigationBar: MobileNavBar(location: location),
      );
    }
    return Scaffold(
      backgroundColor: OrionColors.bgPrimary,
      body: Row(
        children: [
          DesktopRail(location: location, showHarness: platform.canHostHarness),
          Expanded(child: child),
        ],
      ),
    );
  }
}
