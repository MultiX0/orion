import 'dart:ffi';
import 'dart:io';

/// The two user32 calls the harness needs. `package:win32` 6.4 has
/// LockWorkStation but not keybd_event, so both are bound here and the
/// library is opened lazily: importing this file off Windows is harmless.
class WinUser32 {
  WinUser32._(this._lib);

  static WinUser32? _instance;

  /// Null anywhere that is not Windows, or if user32 will not load.
  static WinUser32? open() {
    if (!Platform.isWindows) return null;
    try {
      return _instance ??= WinUser32._(DynamicLibrary.open('user32.dll'));
    } on ArgumentError {
      return null;
    }
  }

  final DynamicLibrary _lib;

  // Virtual key codes. Spelled out because the constant names in win32 move
  // between majors and these numbers do not.
  static const vkVolumeMute = 0xAD;
  static const vkVolumeDown = 0xAE;
  static const vkVolumeUp = 0xAF;
  static const vkMediaNextTrack = 0xB0;
  static const vkMediaPrevTrack = 0xB1;
  static const vkMediaPlayPause = 0xB3;

  static const _keyEventfKeyUp = 0x0002;

  late final _lockWorkStation = _lib
      .lookupFunction<Int32 Function(), int Function()>('LockWorkStation');

  late final _keybdEvent = _lib
      .lookupFunction<
        Void Function(Uint8, Uint8, Uint32, IntPtr),
        void Function(int, int, int, int)
      >('keybd_event');

  bool lockWorkStation() => _lockWorkStation() != 0;

  /// Press and release. Windows routes media keys to whatever is playing.
  void tapKey(int virtualKey) {
    _keybdEvent(virtualKey, 0, 0, 0);
    _keybdEvent(virtualKey, 0, _keyEventfKeyUp, 0);
  }
}
