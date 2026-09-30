import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../../../core/network/device_api.dart';
import '../../../core/result.dart';
import '../../device/domain/device_client.dart';
import '../../device/domain/device_config.dart';
import '../../device/domain/llm_config.dart';
import '../domain/llm_provider.dart';
import '../domain/model_info.dart';
import '../domain/provider_kind.dart';
import '../domain/provider_repository.dart';
import 'model_list_parser.dart';
import 'provider_headers.dart';

/// Talks to OpenAI-compatible endpoints: list the models, prove the key,
/// then hand the config to the board.
class HttpProviderRepository implements ProviderRepository {
  HttpProviderRepository({
    required this.deviceClient,
    this.harnessMirror,
    Dio? dio,
  }) : _dio = dio ?? Dio();

  final DeviceClient deviceClient;

  /// Desktop only, and only when the harness exists. A phone has no dsh, so
  /// this is null there and `mirrorToHarness` is a no-op.
  final HarnessMirror? harnessMirror;

  final Dio _dio;

  @override
  Future<Result<List<ModelInfo>>> listModels(LlmProvider provider) async {
    if (provider.kind == ProviderKind.ollama) {
      final tags = await _get(provider, _ollamaTagsUrl(provider.baseUrl));
      if (tags is Ok<Map<String, dynamic>>) {
        final models = ModelListParser.ollamaTags(tags.value);
        if (models.isNotEmpty) return Ok(models);
      }
    }
    final result = await _get(provider, '${provider.baseUrl}/models');
    return result.map(ModelListParser.openAiList);
  }

  @override
  Future<Result<String>> testCompletion(
    LlmProvider provider,
    String model,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '${provider.baseUrl}/chat/completions',
        options: Options(headers: headersFor(provider)),
        data: <String, dynamic>{
          'model': model,
          'messages': <Map<String, String>>[
            <String, String>{
              'role': 'user',
              'content': 'Say hi in five words.',
            },
          ],
          'max_tokens': 20,
        },
      );
      final reply = _firstChoice(res.data);
      if (reply == null) {
        return const Err(
          ProviderFailure(
            ProviderFailureKind.network,
            'The provider answered without a message',
          ),
        );
      }
      return Ok(reply);
    } on DioException catch (e) {
      return Err(_providerFailure(e, model));
    }
  }

  @override
  Future<Result<String>> describeImage(
    LlmProvider provider,
    String model,
    Uint8List png,
    String prompt,
  ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        '${provider.baseUrl}/chat/completions',
        options: Options(
          headers: headersFor(provider),
          receiveTimeout: const Duration(seconds: 60),
        ),
        data: <String, dynamic>{
          'model': model,
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'role': 'user',
              'content': <Map<String, dynamic>>[
                <String, dynamic>{'type': 'text', 'text': prompt},
                <String, dynamic>{
                  'type': 'image_url',
                  'image_url': <String, dynamic>{
                    'url': 'data:image/png;base64,${base64Encode(png)}',
                  },
                },
              ],
            },
          ],
          'max_tokens': 300,
        },
      );
      final reply = _firstChoice(res.data);
      if (reply == null) {
        return const Err(
          ProviderFailure(
            ProviderFailureKind.badModel,
            'That model did not describe the image. Pick one that sees.',
          ),
        );
      }
      return Ok(reply);
    } on DioException catch (e) {
      return Err(_providerFailure(e, model));
    }
  }

  @override
  Future<Result<void>> validateKey(LlmProvider provider) async {
    final result = await _get(provider, '${provider.baseUrl}/models');
    return result.map((_) {});
  }

  @override
  Future<Result<void>> pushToDevice(LlmProvider provider, String model) async {
    final patch = DeviceConfig(
      llm: LlmConfig(
        baseUrl: provider.baseUrl,
        apiKey: provider.apiKey,
        model: model,
      ),
    );
    final result = await deviceClient.updateConfig(patch);
    return result.map((_) {});
  }

  @override
  Future<Result<void>> mirrorToHarness(
    LlmProvider provider,
    String model,
  ) async => await harnessMirror?.call(provider, model) ?? const Ok(null);

  Future<Result<Map<String, dynamic>>> _get(
    LlmProvider provider,
    String url,
  ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        url,
        options: Options(headers: headersFor(provider)),
      );
      return Ok(res.data ?? const <String, dynamic>{});
    } on DioException catch (e) {
      return Err(_providerFailure(e, null));
    }
  }

  String _ollamaTagsUrl(String baseUrl) {
    final root = baseUrl.endsWith('/v1')
        ? baseUrl.substring(0, baseUrl.length - 3)
        : baseUrl;
    return '${root.endsWith('/') ? root.substring(0, root.length - 1) : root}'
        '/api/tags';
  }

  String? _firstChoice(Map<String, dynamic>? body) {
    final choices = body?['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices.first;
    if (first is! Map<String, dynamic>) return null;
    final message = first['message'];
    if (message is Map<String, dynamic> && message['content'] is String) {
      return (message['content'] as String).trim();
    }
    return null;
  }

  ProviderFailure _providerFailure(DioException e, String? model) {
    final status = e.response?.statusCode;
    if (status == 401 || status == 403) {
      return ProviderFailure(
        ProviderFailureKind.badKey,
        'The provider rejected that key',
        statusCode: status,
      );
    }
    if (status == 404 && model != null) {
      return ProviderFailure(
        ProviderFailureKind.badModel,
        'That provider does not have $model',
        statusCode: status,
      );
    }
    return ProviderFailure(
      ProviderFailureKind.network,
      failureFrom(e).message,
      statusCode: status,
    );
  }
}
