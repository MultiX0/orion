import '../../device/domain/device_mode.dart';

/// One short line per board mode, in the brand voice.
String modeCopy(DeviceMode mode) => switch (mode) {
  DeviceMode.offline => 'Out of reach',
  DeviceMode.idle => 'Quiet, ready',
  DeviceMode.listening => 'Listening',
  DeviceMode.thinking => 'Computing',
  DeviceMode.speaking => 'Speaking',
  DeviceMode.error => 'Something slipped',
};

/// Mono label for status strips and tags.
String modeLabel(DeviceMode mode) => switch (mode) {
  DeviceMode.offline => 'offline',
  DeviceMode.idle => 'idle',
  DeviceMode.listening => 'listening',
  DeviceMode.thinking => 'thinking',
  DeviceMode.speaking => 'speaking',
  DeviceMode.error => 'error',
};
