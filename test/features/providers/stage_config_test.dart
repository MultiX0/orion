import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/device/domain/device_config.dart';
import 'package:orion/features/device/domain/llm_config.dart';
import 'package:orion/features/device/domain/stage_config.dart';
import 'package:orion/features/onboarding/data/ble/config_parts.dart';
import 'package:orion/features/providers/data/http_fish_repository.dart';
import 'package:orion/features/providers/data/stage_blocks.dart';
import 'package:orion/features/providers/data/version1_config.dart';
import 'package:orion/features/providers/domain/fish_config.dart';
import 'package:orion/features/providers/domain/provider_presets.dart';
import 'package:orion/features/providers/domain/voice_stages.dart';

Map<String, dynamic> _fixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test('the masked version 2 config from the contract parses', () {
    final config = DeviceConfig.fromJson(_fixture('config_v2.json'));
    expect(config.llm?.provider, 'deepinfra');
    expect(config.llm?.model, 'google/gemma-4-31B-it-turbo');
    expect(config.stt?.provider, StageProvider.fish);
    expect(config.stt?.model, 'transcribe-1');
    expect(config.tts?.voice, '81c63e6a5ff141d38367fcb009c570d6');
    expect(config.tts?.apiKey, '...9c1d');
  });

  test('the Fish api-credit answer reads as dollars', () {
    expect(parseApiCredit(_fixture('fish_api_credit.json')), 2.15);
    expect(parseApiCredit(const {'credit': '0.000000'}), 0);
    expect(parseApiCredit(const {}), isNull);
  });

  group('blocks', () {
    const fish = FishConfig(voiceId: 'v1', ttsModel: 's2.1-pro-free');

    test('defaults: Gemma on DeepInfra, Fish for both, one key in both', () {
      final blocks = stageBlocks(
        llm: ProviderPresets.deepinfra,
        stages: const VoiceStages(),
        fish: fish,
        keys: (llm: null, stt: 'fish-key', tts: 'fish-key'),
      ).toJson();
      expect(blocks['llm'], {
        'provider': 'deepinfra',
        'base_url': 'https://api.deepinfra.com/v1/openai',
        'model': 'google/gemma-4-31B-it-turbo',
      });
      expect(blocks['stt'], {
        'provider': 'fish',
        'api_key': 'fish-key',
        'model': 'transcribe-1',
      });
      expect(blocks['tts'], {
        'provider': 'fish',
        'api_key': 'fish-key',
        'model': 's2.1-pro-free',
        'voice': 'v1',
      });
    });

    test('an OpenAI-compatible stage carries its base URL and model', () {
      final blocks = stageBlocks(
        llm: ProviderPresets.groq.copyWith(selectedModel: 'llama'),
        stages: const VoiceStages(stt: StageChoice(presetId: 'groq')),
        fish: fish,
        keys: (llm: 'g', stt: 'g', tts: null),
      );
      expect(blocks.llm?.provider, 'groq');
      expect(blocks.stt?.provider, StageProvider.openaiCompatible);
      expect(blocks.stt?.baseUrl, 'https://api.groq.com/openai/v1');
      expect(blocks.stt?.model, 'whisper-large-v3-turbo');
      expect(blocks.tts?.apiKey, isNull, reason: 'no key keeps the stored');
    });

    test('only fields that differ from the board count as changed', () {
      final board = _fixture('config_v2.json');
      final ours = withoutKey(<String, dynamic>{
        'provider': 'fish',
        'api_key': 'new',
        'model': 'transcribe-1',
      });
      expect(differs(ours, withoutKey(board['stt'])), isFalse);
      expect(
        differs({
          ...ours,
          'model': 'transcribe-1-pro',
        }, withoutKey(board['stt'])),
        isTrue,
      );
      expect(differs(ours, null), isTrue);
    });
  });

  test('version 1 gets llm without provider and the Fish half as fish', () {
    const v2 = DeviceConfig(
      llm: LlmConfigFixture.llm,
      stt: SttConfig(provider: 'openai_compatible', model: 'whisper'),
      tts: TtsConfig(
        provider: 'fish',
        apiKey: 'k',
        model: 's2.1-pro-free',
        voice: 'v',
      ),
    );
    expect(toVersion1(v2), {
      'llm': {'base_url': 'u', 'model': 'm'},
      'fish': {'api_key': 'k', 'voice_id': 'v', 'tts_model': 's2.1-pro-free'},
    });
    expect(droppedStages(v2), ['stt']);
  });

  group('orion-config parts', () {
    test('a small config goes whole', () {
      final writes = configWrites(const {
        'llm': {'model': 'm'},
      });
      expect(writes, hasLength(1));
      expect(jsonDecode(utf8.decode(writes.single)), {
        'llm': {'model': 'm'},
      });
    });

    test('a large one goes in parts that join back to the same JSON', () {
      final patch = _fixture('config_v2.json');
      final writes = configWrites(patch, wholeMax: 100, sliceChars: 60);
      expect(writes.length, greaterThan(1));
      final parts = [for (final w in writes) jsonDecode(utf8.decode(w)) as Map];
      expect(parts.map((p) => p['part']), [
        for (var i = 1; i <= writes.length; i++) i,
      ]);
      expect(parts.every((p) => p['parts'] == writes.length), isTrue);
      final joined = parts.map((p) => p['data']).join();
      expect(jsonDecode(joined), patch);
      expect(writes.every((w) => w.length < 512), isTrue);
    });

    test('acks and answers parse, board errors become failures', () {
      expect(parsePartAck(utf8.encode('{"ok":true,"part":2}'), 2).isOk, isTrue);
      expect(
        parsePartAck(utf8.encode('{"ok":true,"part":1}'), 2).isErr,
        isTrue,
      );
      final bad = parseConfigAnswer(
        utf8.encode('{"error":"invalid_config","message":"volume"}'),
      );
      expect(bad.failureOrNull?.message, 'volume');
      expect(parseConfigAnswer(const []).isErr, isTrue);
    });
  });
}

abstract final class LlmConfigFixture {
  static const llm = LlmConfig(provider: 'deepinfra', baseUrl: 'u', model: 'm');
}
