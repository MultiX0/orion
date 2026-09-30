import 'dart:typed_data';

/// Width and height from a JPEG's SOF marker, without decoding the image.
/// An ESP32 camera does not put the size in the part headers, so this is
/// the only honest place to read it.
abstract final class JpegInfo {
  /// Null when the bytes are not a JPEG we understand.
  static (int width, int height)? size(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) return null;
    var i = 2;
    while (i + 9 < bytes.length) {
      if (bytes[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = bytes[i + 1];
      if (_isStartOfFrame(marker)) {
        final height = (bytes[i + 5] << 8) | bytes[i + 6];
        final width = (bytes[i + 7] << 8) | bytes[i + 8];
        return (width, height);
      }
      final length = (bytes[i + 2] << 8) | bytes[i + 3];
      if (length < 2) return null;
      i += 2 + length;
    }
    return null;
  }

  /// Baseline through progressive. C4, C8 and CC are tables, not frames.
  static bool _isStartOfFrame(int marker) =>
      marker >= 0xC0 &&
      marker <= 0xCF &&
      marker != 0xC4 &&
      marker != 0xC8 &&
      marker != 0xCC;
}
