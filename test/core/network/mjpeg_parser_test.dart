import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/jpeg_info.dart';
import 'package:orion/core/network/mjpeg_parser.dart';

/// Two fixtures: a capture from the mock board, and an ESP32-style body with
/// its own boundary token, bare newline headers and a part that leaves out
/// Content-Length, which is what real camera firmware does.
void main() {
  final capture = File('test/fixtures/mjpeg_stream.bin').readAsBytesSync();
  final esp32 = File('test/fixtures/mjpeg_esp32.bin').readAsBytesSync();
  const esp32Boundary = '123456789000000000000987654321';

  Stream<List<int>> inChunks(Uint8List bytes, int size) async* {
    for (var i = 0; i < bytes.length; i += size) {
      yield bytes.sublist(i, (i + size).clamp(0, bytes.length));
    }
  }

  test('yields whole JPEG frames from the capture', () async {
    final frames = await MjpegParser().parse(inChunks(capture, 8192)).toList();

    expect(frames, hasLength(3));
    for (final frame in frames) {
      expect(frame.bytes.sublist(0, 2), <int>[
        0xFF,
        0xD8,
      ], reason: 'JPEG starts');
      expect(frame.bytes.sublist(frame.bytes.length - 2), <int>[
        0xFF,
        0xD9,
      ], reason: 'ends');
    }
  });

  test('does not care where the chunk boundaries fall', () async {
    final big = await MjpegParser().parse(inChunks(capture, 65536)).toList();
    final tiny = await MjpegParser().parse(inChunks(capture, 97)).toList();

    expect(tiny.map((f) => f.bytes.length), big.map((f) => f.bytes.length));
    expect(tiny.first.bytes, big.first.bytes);
  });

  group('a real ESP32 stream', () {
    test('any boundary, bare newlines, Content-Length or not', () async {
      final frames = await MjpegParser(
        boundary: esp32Boundary,
      ).parse(inChunks(esp32, 4096)).toList();

      expect(frames, hasLength(3));
      for (final frame in frames) {
        expect(frame.bytes.sublist(0, 2), <int>[0xFF, 0xD8]);
        expect(frame.bytes.sublist(frame.bytes.length - 2), <int>[0xFF, 0xD9]);
      }
      expect(
        frames.map((f) => f.bytes.length).toSet(),
        hasLength(1),
        reason: 'the same picture three ways is the same bytes three times',
      );
    });

    test('every frame carries its size from the SOF marker', () async {
      final frames = await MjpegParser(
        boundary: esp32Boundary,
      ).parse(inChunks(esp32, 1024)).toList();

      for (final frame in frames) {
        expect(frame.width, 640);
        expect(frame.height, 480);
      }
    });

    test('a chunk that splits a header does not lose the frame', () async {
      final frames = await MjpegParser(
        boundary: esp32Boundary,
      ).parse(inChunks(esp32, 17)).toList();
      expect(frames, hasLength(3));
    });
  });

  test(
    'falls back to the next boundary when there is no content-length',
    () async {
      final body = <int>[
        ...'--frame\r\ncontent-type: image/jpeg\r\n\r\n'.codeUnits,
        0xFF,
        0xD8,
        1,
        2,
        3,
        0xFF,
        0xD9,
        ...'\r\n--frame\r\n'.codeUnits,
      ];
      final frames = await MjpegParser().parse(Stream.value(body)).toList();

      expect(frames, hasLength(1));
      expect(frames.single.bytes, <int>[0xFF, 0xD8, 1, 2, 3, 0xFF, 0xD9]);
      expect(frames.single.width, isNull, reason: 'those bytes have no SOF');
    },
  );

  test('reads the boundary out of a content-type header', () {
    expect(
      MjpegParser.boundaryFrom('multipart/x-mixed-replace; boundary=frame'),
      'frame',
    );
    expect(
      MjpegParser.boundaryFrom('multipart/x-mixed-replace; boundary="--abc"'),
      '--abc',
    );
    expect(
      MjpegParser.boundaryFrom(
        'multipart/x-mixed-replace;boundary=$esp32Boundary',
      ),
      esp32Boundary,
    );
    expect(MjpegParser.boundaryFrom(null), 'frame');
  });

  test('JPEG size comes from the frame marker, not from a header', () {
    final jpeg = File('tool/mock_device/frames/frame_01.jpg').readAsBytesSync();
    expect(JpegInfo.size(jpeg), (640, 480));
    expect(JpegInfo.size(Uint8List.fromList(<int>[1, 2, 3, 4])), isNull);
    expect(JpegInfo.size(Uint8List(0)), isNull);
  });
}
