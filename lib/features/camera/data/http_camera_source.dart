import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/api_paths.dart';
import '../../../core/network/device_api.dart';
import '../../../core/network/jpeg_info.dart';
import '../../../core/network/mjpeg_parser.dart';
import '../../../core/result.dart';
import '../domain/camera_frame.dart';
import '../domain/camera_source.dart';
import 'snapshot_store.dart';

/// MJPEG and stills from the board. The board allows one stream viewer, so
/// the stream opens on listen and closes on cancel.
class HttpCameraSource implements CameraSource {
  HttpCameraSource(this._api, {SnapshotStore? snapshots})
    : _snapshots = snapshots ?? const SnapshotStore();

  /// A board that is rebooting, asleep or already streaming to someone else
  /// is a wait, not an error. Only a board that will never say yes throws.
  static const _busyWait = Duration(seconds: 2);
  static const _firstBackoff = Duration(milliseconds: 300);
  static const _maxBackoff = Duration(seconds: 5);

  final DeviceApi _api;
  final SnapshotStore _snapshots;

  @override
  Stream<CameraFrame> frames() async* {
    var sequence = 0;
    var backoff = _firstBackoff;
    while (true) {
      final cancel = CancelToken();
      final opened = await _api.openStream(
        ApiPaths.stream,
        cancelToken: cancel,
      );
      switch (opened) {
        case Err(:final failure):
          if (_isFatal(failure)) throw failure;
          await Future<void>.delayed(_isBusy(failure) ? _busyWait : backoff);
          backoff = _next(backoff);
          continue;
        case Ok(:final value):
          backoff = _firstBackoff;
          final boundary = MjpegParser.boundaryFrom(
            value.headers['content-type']?.first,
          );
          try {
            final frames = MjpegParser(boundary: boundary).parse(value.stream);
            await for (final frame in frames) {
              yield CameraFrame(
                bytes: frame.bytes,
                receivedAt: DateTime.now(),
                sequence: sequence++,
                width: frame.width,
                height: frame.height,
              );
            }
          } on DioException {
            // The socket dropped mid stream. The board reboots in seconds.
          } on ParseFailure {
            // Garbage on the wire. Reopening costs less than guessing.
          } finally {
            cancel.cancel('camera view closed');
          }
          await Future<void>.delayed(backoff);
          backoff = _next(backoff);
      }
    }
  }

  @override
  Future<Result<CameraFrame>> capture() async {
    final result = await _api.getBytes(ApiPaths.capture);
    return result.map((bytes) {
      final jpeg = Uint8List.fromList(bytes);
      final size = JpegInfo.size(jpeg);
      return CameraFrame(
        bytes: jpeg,
        receivedAt: DateTime.now(),
        width: size?.$1,
        height: size?.$2,
      );
    });
  }

  @override
  Future<Result<String>> saveSnapshot(CameraFrame frame) =>
      _snapshots.write(frame.bytes, at: frame.receivedAt);

  /// 409 is "someone else is watching", which clears on its own.
  static bool _isBusy(Failure failure) =>
      failure is NetworkFailure && failure.statusCode == 409;

  /// A wrong token or a board with no camera never fixes itself.
  static bool _isFatal(Failure failure) =>
      failure is AuthFailure ||
      failure is NotFoundFailure ||
      (failure is NetworkFailure &&
          (failure.statusCode == 401 || failure.statusCode == 404));

  static Duration _next(Duration current) {
    final doubled = current * 2;
    return doubled > _maxBackoff ? _maxBackoff : doubled;
  }
}
