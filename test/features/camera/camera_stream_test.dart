import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/device_api.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/camera/data/http_camera_source.dart';
import 'package:orion/features/camera/data/snapshot_store.dart';
import 'package:orion/features/camera/domain/camera_frame.dart';

/// A stand-in board: it can be busy, it can drop the socket mid stream, and
/// it speaks the ESP32 dialect of multipart.
class _CameraServer {
  _CameraServer(this.jpeg);

  final Uint8List jpeg;
  late final HttpServer _server;
  var requests = 0;

  /// How many of the first requests answer 409, the way a board already
  /// streaming to someone else does.
  int busyFor = 0;

  /// Frames to write before hanging up, so reconnect has something to do.
  int framesPerConnection = 2;

  String get host => '127.0.0.1:${_server.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_serve());
  }

  Future<void> _serve() async {
    await for (final request in _server) {
      requests++;
      if (requests <= busyFor) {
        request.response.statusCode = 409;
        await request.response.close();
        continue;
      }
      request.response.headers.set(
        'content-type',
        'multipart/x-mixed-replace;boundary=espcam',
      );
      for (var i = 0; i < framesPerConnection; i++) {
        request.response
          ..add('--espcam\nContent-Type: image/jpeg\n\n'.codeUnits)
          ..add(jpeg)
          ..add('\n'.codeUnits);
        await request.response.flush();
      }
      // Hang up mid stream, which is what a board does when it reboots.
      await request.response.close();
    }
  }

  Future<void> stop() => _server.close(force: true);
}

void main() {
  final jpeg = File('tool/mock_device/frames/frame_01.jpg').readAsBytesSync();
  late _CameraServer board;
  late Directory temp;

  setUp(() async {
    board = _CameraServer(jpeg);
    await board.start();
    temp = await Directory.systemTemp.createTemp('orion_snaps');
  });

  tearDown(() async {
    await board.stop();
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      return;
    }
  });

  HttpCameraSource sourceFor() => HttpCameraSource(
    DeviceApi(host: board.host),
    snapshots: SnapshotStore(folder: () async => temp),
  );

  test(
    'frames carry the size the board actually sent',
    () async {
      final frame = await sourceFor().frames().first;
      expect(frame.width, 640);
      expect(frame.height, 480);
      expect(frame.bytes.length, jpeg.length);
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'a socket that drops is reopened, and the count keeps going',
    () async {
      final frames = await sourceFor().frames().take(5).toList();

      expect(frames, hasLength(5));
      expect(
        frames.map((f) => f.sequence),
        <int>[0, 1, 2, 3, 4],
        reason: 'a reconnect is not a new stream to the person watching',
      );
      expect(board.requests, greaterThan(1));
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a busy board is waited out, not reported as broken',
    () async {
      board.busyFor = 2;
      final frame = await sourceFor().frames().first;
      expect(frame.width, 640);
      expect(board.requests, 3);
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'a board that is not there at all still throws',
    () async {
      final source = HttpCameraSource(DeviceApi(host: '127.0.0.1:1'));
      await expectLater(
        source.frames().first.timeout(const Duration(seconds: 3)),
        throwsA(anything),
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  group('snapshots', () {
    test('a frame is written as a JPEG and the path comes back', () async {
      final frame = CameraFrame(
        bytes: Uint8List.fromList(jpeg),
        receivedAt: DateTime(2026, 9, 21, 14, 5, 9, 42),
      );
      final path = (await sourceFor().saveSnapshot(frame)).getOrThrow();

      expect(path, endsWith('orion-20260921-140509-042.jpg'));
      expect(await File(path).readAsBytes(), jpeg);
    });

    test('an empty frame is a failure, not an empty file', () async {
      final result = await sourceFor().saveSnapshot(
        CameraFrame(bytes: Uint8List(0), receivedAt: DateTime.now()),
      );
      expect(result.failureOrNull, isA<StorageFailure>());
    });

    test('the name sorts by time', () {
      final first = SnapshotStore.fileName(DateTime(2026, 9, 21, 9, 5));
      final second = SnapshotStore.fileName(DateTime(2026, 9, 21, 10, 5));
      expect(first.compareTo(second), lessThan(0));
    });
  });
}
