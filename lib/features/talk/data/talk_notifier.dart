import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/result.dart';
import '../../device/data/device_providers.dart';
import '../domain/talk_state.dart';

part 'talk_notifier.g.dart';

/// Push to talk and typed queries. Progress shows up in LiveTurn.
@Riverpod(name: 'talkProvider')
class TalkNotifier extends _$TalkNotifier {
  @override
  TalkState build() => const TalkState();

  Future<void> send(String text) =>
      _start(() => ref.read(deviceClientProvider).talk(text: text));

  Future<void> startListening() =>
      _start(() => ref.read(deviceClientProvider).talk());

  Future<void> stop() async {
    await ref.read(deviceClientProvider).stop();
    state = state.copyWith(activeTurnId: null);
  }

  Future<void> _start(Future<Result<String>> Function() action) async {
    state = state.copyWith(isSending: true, error: null);
    final result = await action();
    state = switch (result) {
      Ok(:final value) => state.copyWith(isSending: false, activeTurnId: value),
      Err(:final failure) => state.copyWith(
        isSending: false,
        error: failure.message,
      ),
    };
  }
}
