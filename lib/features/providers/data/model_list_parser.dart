import '../domain/model_info.dart';

/// Reads model lists. Every provider says something slightly different, so
/// anything missing stays null and the UI shows what it has.
abstract final class ModelListParser {
  /// GET {baseUrl}/models on any OpenAI-compatible endpoint.
  static List<ModelInfo> openAiList(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! List) return const <ModelInfo>[];
    final models = <ModelInfo>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      final id = entry['id'] ?? entry['name'];
      if (id is! String || id.isEmpty) continue;
      final meta = entry['metadata'] is Map<String, dynamic>
          ? entry['metadata'] as Map<String, dynamic>
          : const <String, dynamic>{};
      // DeepInfra tags every model with its kind: chat, embed, tts, stt,
      // image-gen, video-gen, plus vision. Tools are never tagged.
      final tags = meta['tags'] is List ? meta['tags'] as List : null;
      models.add(
        ModelInfo(
          id: id,
          displayName: _string(entry['display_name']) ?? _string(meta['name']),
          contextLength: _int(
            entry['context_length'] ??
                entry['max_context_length'] ??
                meta['context_length'] ??
                meta['max_input_tokens'],
          ),
          supportsVision:
              _flag(entry, meta, 'vision') ?? tags?.contains('vision'),
          supportsTools: _flag(entry, meta, 'tools'),
          supportsChat: tags?.contains('chat'),
          supportsSpeechToText: tags?.contains('stt'),
          supportsTextToSpeech: tags?.contains('tts'),
        ),
      );
    }
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  /// GET /api/tags on an Ollama host, which says more than its /v1/models.
  static List<ModelInfo> ollamaTags(Map<String, dynamic> json) {
    final data = json['models'];
    if (data is! List) return const <ModelInfo>[];
    final models = <ModelInfo>[];
    for (final entry in data) {
      if (entry is! Map<String, dynamic>) continue;
      final id = entry['model'] ?? entry['name'];
      if (id is! String || id.isEmpty) continue;
      final details = entry['details'] is Map<String, dynamic>
          ? entry['details'] as Map<String, dynamic>
          : const <String, dynamic>{};
      final family = _string(details['family']);
      final size = _string(details['parameter_size']);
      final label = <String>[?family, ?size].join(' ');
      models.add(
        ModelInfo(
          id: id,
          displayName: label.isEmpty ? null : label,
          supportsVision: family == null
              ? null
              : _visionFamilies.contains(family),
        ),
      );
    }
    models.sort((a, b) => a.id.compareTo(b.id));
    return models;
  }

  static const _visionFamilies = <String>{'llava', 'clip', 'mllama', 'gemma3'};

  /// Providers spell capabilities three ways: a flag, a metadata flag, or an
  /// entry in a capabilities list.
  static bool? _flag(
    Map<String, dynamic> entry,
    Map<String, dynamic> meta,
    String name,
  ) {
    final direct =
        entry['supports_$name'] ??
        meta['supports_$name'] ??
        entry[name] ??
        meta[name];
    if (direct is bool) return direct;
    final caps = entry['capabilities'] ?? meta['capabilities'];
    if (caps is List) return caps.contains(name);
    return null;
  }

  static String? _string(Object? value) =>
      value is String && value.isNotEmpty ? value : null;

  static int? _int(Object? value) => switch (value) {
    final int v => v,
    final num v => v.toInt(),
    final String v => int.tryParse(v),
    _ => null,
  };
}
