import 'package:freezed_annotation/freezed_annotation.dart';

import '../../device/domain/turn_source.dart';
import 'tool_call.dart';
import 'turn_timings.dart';

part 'live_turn.freezed.dart';

/// The turn happening right now, assembled from turn.* socket events before
/// the history endpoint knows about it.
@freezed
abstract class LiveTurn with _$LiveTurn {
  const factory LiveTurn({
    required String turnId,
    @Default(TurnSource.wake) TurnSource source,
    DateTime? startedAt,
    String? transcript,
    String? reply,
    @Default(<ToolCall>[]) List<ToolCall> toolCalls,
    @Default(false) bool isSpeaking,
    @Default(false) bool isDone,
    TurnTimings? timings,
  }) = _LiveTurn;
}
