/// The board's settings, as GET and POST /api/config see them. Config
/// version 2 by default: llm, stt and tts each with a provider. With
/// [version1] it is the old board, with llm and fish only.
class BoardConfig {
  BoardConfig({this.version1 = false}) : values = _defaults(version1);

  final bool version1;
  final Map<String, dynamic> values;

  static const llmProviders = {
    'deepinfra',
    'openai',
    'anthropic',
    'groq',
    'openrouter',
    'ollama',
    'custom',
  };
  static const voiceProviders = {'fish', 'openai_compatible'};

  /// What the firmware accepts: under 48 characters of letters, digits and
  /// the few signs a POSIX TZ string uses.
  static final _posixTz = RegExp(r'^[A-Za-z0-9<>+\-:,./]{1,47}$');

  static Map<String, dynamic> _defaults(bool version1) => <String, dynamic>{
    'device_name': 'Orion',
    'volume': 70,
    'wake_word_enabled': true,
    'language': 'en',
    'time_zone': 'UTC0',
    if (version1) ...<String, dynamic>{
      'llm': <String, dynamic>{
        'base_url': 'https://api.deepinfra.com/v1/openai',
        'api_key': null,
        'model': 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
        'system_prompt': 'You are Orion, a calm assistant with a dry wit.',
      },
      'fish': <String, dynamic>{
        'api_key': null,
        'voice_id': '9a68c1d739134940a4297c996c5ca6a1',
        'tts_model': 's2.1-pro-free',
      },
    } else ...<String, dynamic>{
      'llm': <String, dynamic>{
        'provider': 'deepinfra',
        'base_url': 'https://api.deepinfra.com/v1/openai',
        'api_key': null,
        'model': 'google/gemma-4-31B-it-turbo',
      },
      'stt': <String, dynamic>{
        'provider': 'fish',
        'base_url': null,
        'api_key': null,
        'model': 'transcribe-1',
      },
      'tts': <String, dynamic>{
        'provider': 'fish',
        'base_url': null,
        'api_key': null,
        'model': 's2.1-pro-free',
        'voice': '9a68c1d739134940a4297c996c5ca6a1',
      },
    },
    'pc': <String, dynamic>{
      'enabled': false,
      'base_url': null,
      'token': null,
      'approval': 'ask',
    },
  };

  Map<String, dynamic> get pc => values['pc']! as Map<String, dynamic>;

  /// ask or auto. The board is the source of truth for this one.
  String get approval => '${pc['approval'] ?? 'ask'}';

  Map<String, dynamic>? block(String name) =>
      values[name] as Map<String, dynamic>?;

  /// Merges a partial config one field at a time, so POST /api/config with
  /// only `{ pc: { enabled: true } }` leaves the base URL alone. Returns an
  /// error message and stores nothing when a provider is unknown.
  String? merge(Map<String, dynamic> patch) {
    final next = version1 ? patch : _fromVersion1(patch);
    final problem = version1 ? null : _invalid(next);
    if (problem != null) return problem;
    for (final entry in next.entries) {
      final current = values[entry.key];
      final value = entry.value;
      if (current is Map<String, dynamic> && value is Map<String, dynamic>) {
        for (final field in value.entries) {
          // An empty key clears the stored one.
          current[field.key] = field.key == 'api_key' && field.value == ''
              ? null
              : field.value;
        }
      } else {
        values[entry.key] = value;
      }
    }
    return null;
  }

  /// A version 2 board still takes the version 1 fields: fish maps to tts,
  /// and to stt when that is on Fish; system_prompt is ignored.
  Map<String, dynamic> _fromVersion1(Map<String, dynamic> patch) {
    final out = <String, dynamic>{...patch};
    final llm = out['llm'];
    if (llm is Map<String, dynamic>) {
      out['llm'] = {...llm}..remove('system_prompt');
    }
    final fish = out.remove('fish');
    if (fish is! Map<String, dynamic>) return out;
    final tts = <String, dynamic>{...?out['tts'] as Map<String, dynamic>?};
    if (fish.containsKey('api_key')) tts['api_key'] = fish['api_key'];
    if (fish.containsKey('voice_id')) tts['voice'] = fish['voice_id'];
    if (fish.containsKey('tts_model')) tts['model'] = fish['tts_model'];
    if (tts.isNotEmpty) out['tts'] = tts;
    if (fish.containsKey('api_key') && block('stt')?['provider'] == 'fish') {
      out['stt'] = <String, dynamic>{
        ...?out['stt'] as Map<String, dynamic>?,
        'api_key': fish['api_key'],
      };
    }
    return out;
  }

  String? _invalid(Map<String, dynamic> patch) {
    final llm = patch['llm'];
    if (llm is Map<String, dynamic> &&
        llm['provider'] != null &&
        !llmProviders.contains(llm['provider'])) {
      return 'Unknown llm provider ${llm['provider']}';
    }
    for (final stage in const ['stt', 'tts']) {
      final block = patch[stage];
      if (block is Map<String, dynamic> &&
          block['provider'] != null &&
          !voiceProviders.contains(block['provider'])) {
        return 'Unknown $stage provider ${block['provider']}';
      }
    }
    final volume = patch['volume'];
    if (volume is num && (volume < 0 || volume > 100)) {
      return 'volume is 0 to 100';
    }
    // The board takes a POSIX TZ string and nothing else.
    final tz = patch['time_zone'];
    if (tz != null && (tz is! String || !_posixTz.hasMatch(tz))) {
      return 'time_zone must be a POSIX TZ string such as <+03>-3';
    }
    return null;
  }

  /// POST /api/config/test, scripted: any non-empty key is fine, "bad" is
  /// a 401, "nocredit" on Fish speech to text is a 402, and "busy" plays a
  /// board in the middle of a turn.
  Map<String, dynamic> test(String stage) {
    final block = this.block(stage);
    final key = block?['api_key'];
    if (key == 'busy') return <String, dynamic>{'ok': false, 'error': 'busy'};
    if (key is! String || key.isEmpty || key == 'bad') {
      return <String, dynamic>{
        'ok': false,
        'error': 'http_401',
        'message': 'The provider did not accept the key',
      };
    }
    if (stage == 'stt' && block?['provider'] == 'fish' && key == 'nocredit') {
      return <String, dynamic>{
        'ok': false,
        'error': 'http_402',
        'message': 'Insufficient API credit',
      };
    }
    return <String, dynamic>{'ok': true, 'ms': 412};
  }
}
