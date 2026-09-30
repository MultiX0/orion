import 'package:dio/dio.dart';

import '../result.dart';
import 'api_paths.dart';

/// One board, one dio. Adds the pairing token and turns every error into a
/// typed Failure so callers never see a DioException.
class DeviceApi {
  DeviceApi({
    required String host,
    String? token,
    this.client,
    this.brain,
    Dio? dio,
  }) : _host = normalizeHost(host),
       _dio = dio ?? Dio() {
    _token = token;
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 4)
      ..sendTimeout = const Duration(seconds: 6)
      ..receiveTimeout = const Duration(seconds: 10);
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final token = _token;
          if (token != null) options.headers[ApiPaths.tokenHeader] = token;
          handler.next(options);
        },
      ),
    );
  }

  final Dio _dio;
  final String _host;
  String? _token;

  /// "pc" or "phone": the board lights that app's dot on its idle screen
  /// while this socket stays open. Null for a client that is neither.
  final String? client;

  /// This phone's own brain, "192.168.1.23:7331", which the board sends its
  /// turns to while the link holds. Null on the PC, which has PC control.
  final String? brain;

  String get host => _host;
  String get baseUrl => 'http://$_host';
  Uri get wsUri {
    final query = <String, String>{
      'token': ?_token,
      'client': ?client,
      'brain': ?brain,
    };
    return Uri.parse(
      'ws://$_host${ApiPaths.ws}${query.isEmpty ? '' : '?${Uri(queryParameters: query).query}'}',
    );
  }

  set token(String? value) => _token = value;

  /// Drops the scheme and any trailing slash. "orion.local:8080" and
  /// "http://192.168.1.40/" both end up usable.
  static String normalizeHost(String raw) {
    var host = raw.trim();
    host = host.replaceFirst(RegExp(r'^\w+://'), '');
    while (host.endsWith('/')) {
      host = host.substring(0, host.length - 1);
    }
    return host;
  }

  Future<Result<Map<String, dynamic>>> getJson(
    String path, {
    Map<String, dynamic>? query,
  }) => _send(() => _dio.get<Object>(path, queryParameters: query));

  Future<Result<Map<String, dynamic>>> postJson(
    String path, {
    Map<String, dynamic>? body,
  }) => _send(() => _dio.post<Object>(path, data: body ?? <String, dynamic>{}));

  /// Raw bytes, for /capture.
  Future<Result<List<int>>> getBytes(String path) async {
    try {
      final res = await _dio.get<List<int>>(
        path,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = res.data;
      if (bytes == null) return const Err(ParseFailure('Empty body'));
      return Ok(bytes);
    } on DioException catch (e) {
      return Err(failureFrom(e));
    }
  }

  /// A long lived byte stream, for /stream. The caller cancels it.
  Future<Result<ResponseBody>> openStream(
    String path, {
    CancelToken? cancelToken,
  }) async {
    try {
      final res = await _dio.get<ResponseBody>(
        path,
        cancelToken: cancelToken,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: Duration.zero,
        ),
      );
      final body = res.data;
      if (body == null) return const Err(NetworkFailure('No stream body'));
      return Ok(body);
    } on DioException catch (e) {
      return Err(failureFrom(e));
    }
  }

  Future<void> close() async => _dio.close(force: true);

  Future<Result<Map<String, dynamic>>> _send(
    Future<Response<Object>> Function() call,
  ) async {
    try {
      final res = await call();
      final data = res.data;
      if (data is Map<String, dynamic>) return Ok(data);
      if (data == null || (data is String && data.isEmpty)) {
        return const Ok(<String, dynamic>{});
      }
      return Err(
        ParseFailure('Expected a JSON object, got ${data.runtimeType}'),
      );
    } on DioException catch (e) {
      return Err(failureFrom(e));
    }
  }
}

/// Maps dio's one exception type onto the small Failure family.
Failure failureFrom(DioException e) {
  switch (e.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return TimeoutFailure('Orion did not answer in time (${e.type.name})');
    case DioExceptionType.cancel:
      return const NetworkFailure('Request cancelled');
    case DioExceptionType.connectionError:
    case DioExceptionType.unknown:
      return NetworkFailure(e.message ?? 'Could not reach Orion');
    case DioExceptionType.badCertificate:
      return const NetworkFailure('The board presented a bad certificate');
    case DioExceptionType.badResponse:
      return _fromStatus(e.response);
    default:
      return NetworkFailure(e.message ?? 'The request failed');
  }
}

Failure _fromStatus(Response<Object?>? response) {
  final status = response?.statusCode ?? 0;
  final data = response?.data;
  final body = data is Map<String, dynamic> ? data : const <String, dynamic>{};
  final code = body['error'] as String?;
  final message = body['message'] as String? ?? 'The board returned $status';

  if (status == 401 || status == 403) return AuthFailure(message);
  if (status == 404) return NotFoundFailure(message);
  if (code != null) return DeviceFailure(code, message);
  return NetworkFailure(message, statusCode: status);
}
