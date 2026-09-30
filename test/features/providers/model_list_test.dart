import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/providers/data/model_list_parser.dart';
import 'package:orion/features/providers/data/provider_headers.dart';
import 'package:orion/features/providers/domain/provider_presets.dart';

/// Recorded answers from each provider, trimmed to a few entries.
void main() {
  Map<String, dynamic> fixture(String name) =>
      jsonDecode(File('test/fixtures/$name').readAsStringSync())
          as Map<String, dynamic>;

  test('OpenAI models parse, ids intact and sorted', () {
    final models = ModelListParser.openAiList(fixture('models_openai.json'));

    expect(models.map((m) => m.id), ['gpt-4o', 'gpt-4o-mini', 'o3-mini']);
    expect(models.first.contextLength, isNull);
    expect(models.first.supportsVision, isNull);
  });

  test('Anthropic display names survive', () {
    final models = ModelListParser.openAiList(fixture('models_anthropic.json'));

    expect(models, hasLength(2));
    expect(
      models.firstWhere((m) => m.id.startsWith('claude-sonnet')).displayName,
      'Claude Sonnet 4.5',
    );
  });

  test('DeepInfra metadata gives context length and the badges', () {
    final models = ModelListParser.openAiList(fixture('models_deepinfra.json'));
    final vision = models.firstWhere((m) => m.id.contains('Vision'));
    final llama = models.firstWhere((m) => m.id.endsWith('3.3-70B-Instruct'));
    final qwen = models.firstWhere((m) => m.id.startsWith('Qwen'));

    expect(vision.supportsVision, isTrue);
    expect(vision.supportsTools, isTrue);
    expect(vision.contextLength, 131072);
    expect(llama.supportsVision, isFalse, reason: 'tools only');
    expect(llama.displayName, 'Llama 3.3 70B Instruct');
    expect(qwen.contextLength, 32768);
    expect(qwen.supportsTools, isFalse);
  });

  test('DeepInfra tags tell chat models from the rest', () {
    final models = ModelListParser.openAiList(fixture('models_deepinfra.json'));
    final gemma = models.firstWhere((m) => m.id.startsWith('google/gemma'));
    final embed = models.firstWhere((m) => m.id == 'BAAI/bge-m3');
    final llama = models.firstWhere((m) => m.id.endsWith('3.3-70B-Instruct'));

    expect(gemma.supportsChat, isTrue);
    expect(gemma.supportsVision, isTrue);
    expect(gemma.supportsTools, isNull, reason: 'tags never mention tools');
    expect(gemma.contextLength, 262144);
    expect(embed.supportsChat, isFalse);
    expect(llama.supportsChat, isNull, reason: 'no tags, no claim');
  });

  test('DeepInfra tags speech models as stt and tts', () {
    final models = ModelListParser.openAiList(fixture('models_deepinfra.json'));
    final whisper = models.firstWhere((m) => m.id.contains('whisper'));
    final kokoro = models.firstWhere((m) => m.id.contains('Kokoro'));
    final gemma = models.firstWhere((m) => m.id.startsWith('google/gemma'));
    final llama = models.firstWhere((m) => m.id.endsWith('3.3-70B-Instruct'));

    expect(whisper.supportsSpeechToText, isTrue);
    expect(whisper.supportsTextToSpeech, isFalse);
    expect(whisper.supportsChat, isFalse);
    expect(kokoro.supportsTextToSpeech, isTrue);
    expect(kokoro.supportsSpeechToText, isFalse);
    expect(gemma.supportsSpeechToText, isFalse);
    expect(llama.supportsSpeechToText, isNull, reason: 'no tags, no claim');
  });

  test('Ollama tags give a label and spot a vision family', () {
    final models = ModelListParser.ollamaTags(fixture('ollama_tags.json'));

    expect(models.map((m) => m.id), ['llama3.2:latest', 'llava:7b']);
    expect(models.first.displayName, 'llama 3.2B');
    expect(models.first.supportsVision, isFalse);
    expect(models.last.supportsVision, isTrue);
  });

  test('junk in the list is skipped, not fatal', () {
    final models = ModelListParser.openAiList(const <String, dynamic>{
      'data': <dynamic>[
        'not a model',
        <String, dynamic>{'no_id': true},
        <String, dynamic>{'id': 'good-one'},
      ],
    });

    expect(models.map((m) => m.id), ['good-one']);
    expect(ModelListParser.openAiList(const <String, dynamic>{}), isEmpty);
  });

  test('each provider kind sends the headers it needs', () {
    expect(
      headersFor(ProviderPresets.openai.copyWith(apiKey: 'sk-test')),
      containsPair('authorization', 'Bearer sk-test'),
    );

    final anthropic = headersFor(
      ProviderPresets.anthropic.copyWith(apiKey: 'sk-ant-test'),
    );
    expect(anthropic['x-api-key'], 'sk-ant-test');
    expect(anthropic['anthropic-version'], '2023-06-01');

    expect(headersFor(ProviderPresets.ollama), isEmpty);
  });
}
