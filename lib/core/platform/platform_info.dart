import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'platform_info.g.dart';

/// The one place that knows which OS we are on. Screens ask this, never dart:io.
class PlatformInfo {
  const PlatformInfo({
    required this.isMobile,
    required this.isDesktop,
    required this.canHostHarness,
    required this.hasTouch,
    required this.osName,
    this.canUseBluetooth = false,
  });

  factory PlatformInfo.detect() {
    if (kIsWeb) {
      return const PlatformInfo(
        isMobile: false,
        isDesktop: true,
        canHostHarness: false,
        hasTouch: false,
        osName: 'web',
      );
    }
    final isMobile = Platform.isAndroid || Platform.isIOS;
    final isDesktop =
        Platform.isWindows || Platform.isLinux || Platform.isMacOS;
    return PlatformInfo(
      isMobile: isMobile,
      isDesktop: isDesktop,
      canHostHarness: Platform.isWindows || Platform.isLinux,
      hasTouch: isMobile,
      osName: Platform.operatingSystem,
      // Phones, and Windows through WinRT: a board that has never been on
      // Wi-Fi answers nothing on the LAN, so the PC needs Bluetooth to set
      // one up on its own. Linux and macOS are not tested yet.
      canUseBluetooth: isMobile || Platform.isWindows,
    );
  }

  final bool isMobile;
  final bool isDesktop;
  final bool canHostHarness;
  final bool hasTouch;
  final String osName;

  /// True where the board can be set up over Bluetooth LE.
  final bool canUseBluetooth;
}

@Riverpod(keepAlive: true)
PlatformInfo platformInfo(Ref ref) => PlatformInfo.detect();
