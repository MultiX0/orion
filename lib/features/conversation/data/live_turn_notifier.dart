import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../device/data/device_providers.dart';
import '../../device/domain/ws_event.dart';
import '../domain/live_turn.dart';
import '../domain/tool_call.dart';
import 'conversation_providers.dart';

part 'live_turn_notifier.g.dart';

/// Follows turn.* socket events into one LiveTurn. Null between turns
/// until the first one of the session starts.
@Riverpod(keepAlive: true, name: 'liveTurnProvider')
class LiveTurnNotifier extends _$LiveTurnNotifier {
  @override
  LiveTurn? build() {
    ref.listen(deviceEventsProvider, (_, next) {
      final event = next.value;
      if (event != null) _apply(event);
    });
    return null;
  }

  void _apply(WsEvent event) {
    if (event case WsTurnStartEvent(:final turnId, :final source, :final ts)) {
      state = LiveTurn(turnId: turnId, source: source, startedAt: ts);
      return;
    }
    final current = state;
    if (current == null) return;
    state = switch (event) {
      WsTurnTranscriptEvent(:final turnId, :final text)
          when turnId == current.turnId =>
        current.copyWith(transcript: text),
      WsTurnReplyEvent(:final turnId, :final text)
          when turnId == current.turnId =>
        current.copyWith(reply: text),
      WsTurnToolEvent(:final turnId, :final toolCall)
          when turnId == current.turnId =>
        current.copyWith(toolCalls: _upsert(current.toolCalls, toolCall)),
      WsTtsStartEvent(:final turnId) when turnId == current.turnId =>
        current.copyWith(isSpeaking: true),
      WsTtsEndEvent(:final turnId) when turnId == current.turnId =>
        current.copyWith(isSpeaking: false),
      WsTurnEndEvent(:final turnId, :final timingsMs)
          when turnId == current.turnId =>
        current.copyWith(isDone: true, isSpeaking: false, timings: timingsMs),
      _ => current,
    };
    if (event is WsTurnEndEvent) ref.invalidate(turnsProvider);
  }

  /// The second turn.tool event only carries id, status and result.
  List<ToolCall> _upsert(List<ToolCall> calls, ToolCall delta) {
    final index = calls.indexWhere((c) => c.id == delta.id);
    if (index < 0) return [...calls, delta];
    final known = calls[index];
    final merged = known.copyWith(
      status: delta.status,
      result: delta.result ?? known.result,
      name: delta.name.isEmpty ? known.name : delta.name,
      args: delta.args.isEmpty ? known.args : delta.args,
    );
    return [...calls]..[index] = merged;
  }
}
