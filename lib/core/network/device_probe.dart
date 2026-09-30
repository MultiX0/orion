import 'package:dio/dio.dart';

import '../../features/device/domain/device.dart';
import '../../features/device/domain/device_info.dart';
import '../result.dart';
import 'api_paths.dart';
import 'device_api.dart';

/// Asks one host for /api/info. Discovery never shows a board it has not
/// heard from directly, so a stale mDNS record or a beacon from a board that
/// has since moved cannot turn into a card the user can tap.
class DeviceProbe {
  DeviceProbe({Dio? dio, this.timeout = const Duration(milliseconds: 400)})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: timeout,
              sendTimeout: timeout,
              receiveTimeout: timeout,
              validateStatus: (status) => status != null && status < 500,
            ),
          );

  /// 400 ms for a sweep, where most hosts never answer. Manual entry uses a
  /// patient one.
  final Duration timeout;
  final Dio _dio;

  Future<Result<Device>> probe(String host, {String source = 'manual'}) async {
    final normalized = DeviceApi.normalizeHost(host);
    if (normalized.isEmpty) {
      return const Err(NetworkFailure('Enter an address first'));
    }
    try {
      final res = await _dio
          .get<Object>('http://$normalized${ApiPaths.info}')
          .timeout(timeout + const Duration(milliseconds: 200));
      final body = res.data;
      if (body is! Map<String, dynamic>) {
        return const Err(ParseFailure('That host answered, but not as JSON'));
      }
      return toDevice(body, normalized, source);
    } on Object catch (e) {
      // Nearly every address in a sweep refuses or times out. That is the
      // normal case, not an error worth a type test.
      return Err(NetworkFailure(_short(e)));
    }
  }

  /// Pure, so the shape of /api/info is a test.
  static Result<Device> toDevice(
    Map<String, dynamic> json,
    String host,
    String source,
  ) {
    try {
      final info = DeviceInfo.fromJson(json);
      if (info.deviceId.isEmpty) {
        return const Err(ParseFailure('That board sent no device id'));
      }
      return Ok(
        Device(
          id: info.deviceId,
          name: info.name,
          host: host,
          fwVersion: info.fwVersion,
          source: source,
        ),
      );
    } on Object catch (e) {
      return Err(ParseFailure('That host answered, but not like a board: $e'));
    }
  }

  void close() => _dio.close(force: true);

  static String _short(Object error) {
    final status = error is DioException ? error.response?.statusCode : null;
    if (status != null) return 'That host answered with $status, not a board';
    return 'No board answered at that address';
  }
}
