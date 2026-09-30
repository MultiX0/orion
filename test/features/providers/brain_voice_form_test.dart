import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/storage/in_memory_secret_store.dart';
import 'package:orion/core/storage/secret_store.dart';
import 'package:orion/core/storage/storage_providers.dart';
import 'package:orion/core/theme/theme.dart';
import 'package:orion/core/use_fakes.dart';
import 'package:orion/features/onboarding/presentation/brain_voice_step.dart';
import 'package:orion/features/providers/data/board_config_providers.dart';
import 'package:orion/features/providers/data/http_board_config_repository.dart';
import 'package:orion/features/providers/domain/board_config_repository.dart';
import 'package:orion/features/providers/presentation/stages/get_fish_key_button.dart';
import 'package:orion/features/providers/presentation/stages/stage_test_row.dart';

void main() {
  late InMemorySecretStore secrets;
  late FakeBoardConfigRepository board;
  late List<Uri> opened;

  // A small phone: 360 wide. Tall, so every card is on screen at once.
  Future<void> pump(WidgetTester tester, {Map<String, String>? keys}) async {
    secrets = InMemorySecretStore();
    for (final MapEntry(:key, :value) in (keys ?? {}).entries) {
      await secrets.write(key, value);
    }
    board = FakeBoardConfigRepository();
    opened = [];
    await tester.binding.setSurfaceSize(const Size(360, 4200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          useFakesProvider.overrideWithValue(true),
          secretStoreProvider.overrideWithValue(secrets),
          boardConfigRepositoryProvider.overrideWithValue(board),
          linkOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          theme: buildOrionTheme(),
          home: const Scaffold(
            body: BrainVoiceStep(ordinal: '04', reduced: true),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.tap(find.text(text).first);
    await settle(tester);
  }

  testWidgets('defaults: Fish for both, one key serves both, no overflow', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Serves both speaking and listening.'), findsOneWidget);
    expect(find.text('google/gemma-4-31B-it-turbo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Fish speaks in Orion Voice only, no library to pick from', (
    tester,
  ) async {
    await pump(tester, keys: {SecretKeys.fishApiKey: 'fish-key'});
    expect(find.text('Orion Voice'), findsOneWidget);
    expect(find.text('Search the library by title'), findsNothing);
    expect(find.text('reference_id from fish.audio'), findsNothing);
    expect(find.text('Preview voice'), findsOneWidget);
  });

  testWidgets('with only a Fish key, Send puts the same key in both blocks', (
    tester,
  ) async {
    await pump(tester, keys: {SecretKeys.fishApiKey: 'fish-key'});
    await tapText(tester, 'Send to Orion');
    expect(board.stored.stt?.provider, 'fish');
    expect(board.stored.stt?.model, 'transcribe-1');
    expect(board.stored.tts?.model, 's2.1-pro-free');
    expect(board.stored.stt?.apiKey, 'fish-key');
    expect(board.stored.tts?.apiKey, 'fish-key');
    expect(board.stored.llm?.model, 'google/gemma-4-31B-it-turbo');
    expect(board.stored.llm?.apiKey, isNull, reason: 'keeps the board key');
  });

  testWidgets('moving listening off Fish splits the key and drops the note', (
    tester,
  ) async {
    await pump(tester);
    expect(find.textContaining(r'$0.36 per hour'), findsOneWidget);
    await tapText(tester, 'Groq');
    expect(find.text('Serves speaking.'), findsOneWidget);
    expect(find.textContaining(r'$0.36 per hour'), findsNothing);
    expect(find.text('whisper-large-v3-turbo'), findsWidgets);
  });

  testWidgets('the credit note shows the balance and the hours it buys', (
    tester,
  ) async {
    await pump(tester, keys: {SecretKeys.fishApiKey: 'fish-key'});
    expect(
      find.text(
        r'This account has $2.00 of API credit, about 5.6 hours of listening.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('the key button opens exactly the Fish link', (tester) async {
    await pump(tester);
    await tapText(tester, 'Get your Fish Audio API key');
    expect(opened.single.toString(), fishKeyUrl);
    expect(fishKeyUrl, 'https://fish.audio?fpr=d9z5u5&fp_sid=ipdev');
  });

  testWidgets('Test says no credit for a Fish 402 and wrong key for a 401', (
    tester,
  ) async {
    await pump(
      tester,
      keys: {
        SecretKeys.fishApiKey: 'nocredit',
        SecretKeys.providerApiKey('deepinfra'): 'bad',
      },
    );
    final tests = find.text('Test');
    await tester.tap(tests.at(1)); // listening
    await settle(tester);
    expect(find.textContaining('Top up at least'), findsOneWidget);
    await tester.tap(tests.at(2)); // mind
    await settle(tester);
    expect(find.textContaining('The key was turned down'), findsOneWidget);
  });

  test('plain words for every test answer', () {
    String copy(String error, {bool fish = false}) =>
        testCopy(StageTestResult(ok: false, error: error), fish: fish);
    expect(copy('busy'), 'Orion is talking, trying again.');
    expect(copy('http_402', fish: true), contains(r'at least $1'));
    expect(copy('timeout'), contains('did not answer in time'));
    expect(copy('unreachable'), contains('could not reach'));
    expect(
      testCopy(const StageTestResult(ok: true, ms: 380), fish: true),
      contains('380 ms'),
    );
  });
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
