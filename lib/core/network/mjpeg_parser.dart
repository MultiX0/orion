import 'dart:convert';
import 'dart:typed_data';

import '../result.dart';
import 'jpeg_info.dart';

/// One frame off the wire, with the size read from the JPEG itself.
class MjpegFrame {
  const MjpegFrame(this.bytes, {this.width, this.height});

  final Uint8List bytes;
  final int? width;
  final int? height;
}

/// Splits a multipart/x-mixed-replace body into whole JPEG frames.
/// Chunks arrive at any size, so state lives between them. A real ESP32
/// picks its own boundary token, may leave out Content-Length and may end
/// its headers with a bare newline, so all three are accepted.
class MjpegParser {
  MjpegParser({this.boundary = 'frame', this.maxFrameBytes = 4 * 1024 * 1024});

  final String boundary;

  /// A frame bigger than this means the stream is not what it claims to be.
  final int maxFrameBytes;

  static const _crlfCrlf = <int>[13, 10, 13, 10];
  static const _lfLf = <int>[10, 10];

  /// Reads the boundary out of a content-type header. Falls back to "frame",
  /// which is what the board sends.
  static String boundaryFrom(String? contentType) {
    if (contentType == null) return 'frame';
    final match = RegExp(
      r'boundary=("?)([^";]+)\1',
      caseSensitive: false,
    ).firstMatch(contentType);
    return match?.group(2)?.trim() ?? 'frame';
  }

  Stream<MjpegFrame> parse(Stream<List<int>> source) async* {
    final marker = ascii.encode('--$boundary');
    var buffer = Uint8List(0);

    await for (final chunk in source) {
      buffer = _join(buffer, chunk);
      while (true) {
        final start = _indexOf(buffer, marker, 0);
        if (start < 0) break;
        final headers = _headerEnd(buffer, start);
        if (headers == null) break;

        final bodyStart = headers.$1;
        final headerText = ascii.decode(
          buffer.sublist(start, headers.$2),
          allowInvalid: true,
        );
        final declared = _contentLength(headerText);

        int bodyEnd;
        if (declared != null) {
          if (declared > maxFrameBytes) {
            throw ParseFailure('MJPEG frame of $declared bytes is too big');
          }
          bodyEnd = bodyStart + declared;
          if (buffer.length < bodyEnd) break;
        } else {
          final next = _indexOf(buffer, marker, bodyStart);
          if (next < 0) break;
          bodyEnd = _trimLineEnd(buffer, bodyStart, next);
        }

        if (bodyEnd > bodyStart) {
          yield _frame(Uint8List.fromList(buffer.sublist(bodyStart, bodyEnd)));
        }
        buffer = Uint8List.fromList(buffer.sublist(bodyEnd));
      }

      if (buffer.length > maxFrameBytes) {
        throw const ParseFailure('MJPEG stream has no boundary in sight');
      }
    }
  }

  static MjpegFrame _frame(Uint8List bytes) {
    final size = JpegInfo.size(bytes);
    return MjpegFrame(bytes, width: size?.$1, height: size?.$2);
  }

  /// Where the body starts and where the headers end. CRLF CRLF or LF LF,
  /// whichever comes first.
  (int, int)? _headerEnd(Uint8List buffer, int from) {
    final crlf = _indexOf(buffer, _crlfCrlf, from);
    final lf = _indexOf(buffer, _lfLf, from);
    if (crlf < 0 && lf < 0) return null;
    if (crlf >= 0 && (lf < 0 || crlf <= lf)) {
      return (crlf + _crlfCrlf.length, crlf);
    }
    return (lf + _lfLf.length, lf);
  }

  /// The newline before the next boundary belongs to the protocol, not the
  /// picture. One byte or two, depending on who wrote the firmware.
  static int _trimLineEnd(Uint8List buffer, int bodyStart, int next) {
    var end = next;
    if (end > bodyStart && buffer[end - 1] == 10) end--;
    if (end > bodyStart && buffer[end - 1] == 13) end--;
    return end;
  }

  int? _contentLength(String headers) {
    final match = RegExp(
      r'content-length:\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(headers);
    return match == null ? null : int.tryParse(match.group(1)!);
  }

  Uint8List _join(Uint8List head, List<int> tail) {
    if (head.isEmpty) return Uint8List.fromList(tail);
    final out = Uint8List(head.length + tail.length)
      ..setRange(0, head.length, head)
      ..setRange(head.length, head.length + tail.length, tail);
    return out;
  }

  int _indexOf(Uint8List haystack, List<int> needle, int from) {
    final last = haystack.length - needle.length;
    for (var i = from; i <= last; i++) {
      var hit = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          hit = false;
          break;
        }
      }
      if (hit) return i;
    }
    return -1;
  }
}
