import 'package:freezed_annotation/freezed_annotation.dart';

import 'tool_call.dart';
import 'turn_timings.dart';

part 'turn.freezed.dart';
part 'turn.g.dart';

/// One finished exchange from GET /api/history.
@freezed
abstract class Turn with _$Turn {
  const factory Turn({
    required String id,
    required DateTime startedAt,
    String? transcript,
    String? reply,
    @Default(false) bool hadImage,
    @Default(<ToolCall>[]) List<ToolCall> toolCalls,
    TurnTimings? timingsMs,
  }) = _Turn;

  factory Turn.fromJson(Map<String, dynamic> json) => _$TurnFromJson(json);
}
