import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../conversation/data/conversation_providers.dart';
import '../../conversation/data/live_turn_notifier.dart';
import '../domain/last_exchange.dart';

part 'home_providers.g.dart';

/// The live turn while one runs, otherwise the newest turn from history.
@riverpod
LastExchange lastExchange(Ref ref) {
  final live = ref.watch(liveTurnProvider);
  if (live != null) {
    return LastExchange(
      transcript: live.transcript,
      reply: live.reply,
      isLive: !live.isDone,
    );
  }
  final last = ref.watch(turnsProvider).value?.firstOrNull;
  return LastExchange(transcript: last?.transcript, reply: last?.reply);
}
