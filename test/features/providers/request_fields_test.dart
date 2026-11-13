import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/providers/data/request_fields.dart';
import 'package:orion/features/providers/domain/provider_presets.dart';

void main() {
  setUp(RequestFields.forgetLearned);

  test(
    'Anthropic gets no temperature, max_tokens, and thinking off for a spoken answer',
    () {
      final f = RequestFields.of(
        ProviderPresets.anthropic,
        'claude-haiku-5-5',
        maxTokens: 600,
        temperature: 0.6,
      );
      expect(f, {
        'max_tokens': 600,
        'thinking': {'type': 'disabled'},
      });
      // The thinking model of the PC brain thinks, with room for it.
      expect(
        RequestFields.of(
          ProviderPresets.anthropic,
          'claude-haiku-5-5',
          maxTokens: 600,
          thinking: true,
        ),
        {'max_tokens': 2000},
      );
    },
  );

  test(
    'a Claude model that refuses thinking off is learned: it thinks, with room',
    () {
      const m = 'claude-opus-5-5';
      expect(
        RequestFields.learn(
          ProviderPresets.anthropic,
          m,
          '"thinking.type.disabled" is not supported for this model',
        ),
        isTrue,
      );
      expect(RequestFields.of(ProviderPresets.anthropic, m, maxTokens: 20), {
        'max_tokens': 2000,
      });
      expect(
        RequestFields.learn(
          ProviderPresets.anthropic,
          m,
          '"thinking.type.disabled" is not supported',
        ),
        isFalse,
      );
    },
  );

  test('Sonnet 5.5 names its own way to stop thinking, and gets it', () {
    const m = 'claude-sonnet-5-5';
    expect(
      RequestFields.learn(
        ProviderPresets.anthropic,
        m,
        'To turn thinking off on this model, send "thinking": {"type": "between_tools"} instead of {"type": "disabled"}.',
      ),
      isTrue,
    );
    expect(RequestFields.of(ProviderPresets.anthropic, m, maxTokens: 600), {
      'max_tokens': 600,
      'thinking': {'type': 'between_tools'},
    });
  });

  test(
    'OpenAI gets max_completion_tokens, at least 200, and no temperature',
    () {
      expect(
        RequestFields.of(
          ProviderPresets.openai,
          'gpt-5-mini',
          maxTokens: 20,
          temperature: 0.6,
        ),
        {'max_completion_tokens': 200},
      );
      expect(
        RequestFields.of(
          ProviderPresets.openai,
          'gpt-5-mini',
          maxTokens: 4000,
          temperature: 0.6,
        ),
        {'max_completion_tokens': 4000},
      );
    },
  );

  test('everyone else keeps both, and no temperature when none is asked', () {
    expect(
      RequestFields.of(
        ProviderPresets.deepinfra,
        'm',
        maxTokens: 600,
        temperature: 0.6,
      ),
      {'max_tokens': 600, 'temperature': 0.6},
    );
    expect(RequestFields.of(ProviderPresets.groq, 'm', maxTokens: 20), {
      'max_tokens': 20,
    });
  });

  test('a custom server that refuses a field is learned, per model', () {
    final p = ProviderPresets.custom.copyWith(baseUrl: 'http://box:8000/v1');
    expect(
      RequestFields.learn(
        p,
        'm1',
        '{"error":"`temperature` is deprecated for this model."}',
      ),
      isTrue,
    );
    expect(RequestFields.of(p, 'm1', maxTokens: 10, temperature: 0.6), {
      'max_tokens': 10,
    });
    // The other model on the same server is untouched.
    expect(RequestFields.of(p, 'm2', maxTokens: 10, temperature: 0.6), {
      'max_tokens': 10,
      'temperature': 0.6,
    });

    expect(
      RequestFields.learn(
        p,
        'm1',
        "Unsupported parameter: 'max_tokens'. Use 'max_completion_tokens' instead.",
      ),
      isTrue,
    );
    expect(RequestFields.of(p, 'm1', maxTokens: 300, temperature: 0.6), {
      'max_completion_tokens': 300,
    });
    // Nothing more to learn: the caller does not send the same request again.
    expect(
      RequestFields.learn(
        p,
        'm1',
        'temperature max_tokens max_completion_tokens',
      ),
      isFalse,
    );
    expect(RequestFields.learn(p, 'm2', 'rate limited'), isFalse);
  });
}
