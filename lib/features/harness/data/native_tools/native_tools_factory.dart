import '../../domain/native_tools.dart';
import 'linux_tools.dart';
import 'unsupported_tools.dart';
import 'windows_tools.dart';

/// The one place that picks an implementation, from the OS name PlatformInfo
/// already carries. Nothing else in the harness touches dart:io Platform.
NativeTools nativeToolsFor(String osName) => switch (osName) {
  'windows' => WindowsTools(),
  'linux' => LinuxTools(),
  _ => const UnsupportedTools(),
};
