import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/device_api.dart';
import '../../../core/result.dart';
import '../../device/domain/device_client.dart';
import '../../device/domain/device_config.dart';
import '../domain/fish_config.dart';
import '../domain/fish_repository.dart';

/// Fish Audio. The app only previews a voice, the board does the real TTS.
class HttpFishRepository implements FishRepository {
  HttpFishRepository({required this.deviceClient, Dio? dio})
    : _dio = dio ?? Dio();

  static const baseUrl = 'https://api.fish.audio';
  static const ttsUrl = '$baseUrl/v1/tts';
  static const modelUrl = '$baseUrl/model';
  static const creditUrl = '$baseUrl/wallet/self/api-credit';

  final DeviceClient deviceClient;
  final Dio _dio;

  @override
  Future<Result<Uint8List>> previewVoice(
    FishConfig config, {
    String text = "Hi, I'm Orion.",
  }) async {
    final key = config.apiKey;
    if (key == null || key.isEmpty) {
      return const Err(
        ProviderFailure(ProviderFailureKind.badKey, 'Add a Fish Audio key'),
      );
    }
    try {
      final res = await _dio.post<List<int>>(
        ttsUrl,
        options: Options(
          responseType: ResponseType.bytes,
          headers: <String, String>{
            'authorization': 'Bearer $key',
            'model': config.ttsModel,
          },
        ),
        data: <String, dynamic>{
          'text': text,
          'reference_id': ?config.voiceId,
          'format': 'mp3',
          // A preview is short and the user is waiting, so trade a little
          // quality for the first byte.
          'latency': 'balanced',
        },
      );
      final bytes = res.data;
      if (bytes == null || bytes.isEmpty) {
        return const Err(
          ProviderFailure(ProviderFailureKind.network, 'Fish sent no audio'),
        );
      }
      return Ok(Uint8List.fromList(bytes));
    } on DioException catch (e) {
      return Err(_fishFailure(e));
    }
  }

  /// The cheapest call that proves a key: one of the workspace's own voices.
  @override
  Future<Result<void>> validateKey(String apiKey) async {
    if (apiKey.trim().isEmpty) {
      return const Err(
        ProviderFailure(ProviderFailureKind.badKey, 'Add a Fish Audio key'),
      );
    }
    final result = await _getModels(apiKey, <String, dynamic>{
      'self': true,
      'page_size': 1,
    });
    return result.map((_) {});
  }

  @override
  Future<Result<double>> apiCredit(String apiKey) async {
    if (apiKey.trim().isEmpty) {
      return const Err(
        ProviderFailure(ProviderFailureKind.badKey, 'Add a Fish Audio key'),
      );
    }
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        creditUrl,
        options: Options(
          headers: <String, String>{'authorization': 'Bearer $apiKey'},
        ),
      );
      final credit = parseApiCredit(res.data ?? const <String, dynamic>{});
      if (credit == null) {
        return const Err(ParseFailure('Fish sent no credit figure'));
      }
      return Ok(credit);
    } on DioException catch (e) {
      return Err(_fishFailure(e));
    }
  }

  Future<Result<Map<String, dynamic>>> _getModels(
    String apiKey,
    Map<String, dynamic> query,
  ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        modelUrl,
        queryParameters: query,
        options: Options(
          headers: <String, String>{'authorization': 'Bearer $apiKey'},
        ),
      );
      return Ok(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return Err(_fishFailure(e));
    }
  }

  static ProviderFailure _fishFailure(DioException e) {
    final status = e.response?.statusCode;
    return switch (status) {
      401 || 403 => ProviderFailure(
        ProviderFailureKind.badKey,
        'Fish Audio did not accept that key',
        statusCode: status,
      ),
      402 => ProviderFailure(
        ProviderFailureKind.network,
        'No Fish API credit for that model. Pick s2.1-pro-free, or add '
        'credit at fish.audio/app/developers.',
        statusCode: status,
      ),
      _ => ProviderFailure(
        ProviderFailureKind.network,
        failureFrom(e).message,
        statusCode: status,
      ),
    };
  }

  @override
  Future<Result<void>> pushToDevice(FishConfig config) async {
    final result = await deviceClient.updateConfig(DeviceConfig(fish: config));
    return result.map((_) {});
  }
}

/// `credit` is a decimal string of dollars, for example "0.000000".
double? parseApiCredit(Map<String, dynamic> json) {
  final credit = json['credit'];
  if (credit is num) return credit.toDouble();
  if (credit is String) return double.tryParse(credit);
  return null;
}
