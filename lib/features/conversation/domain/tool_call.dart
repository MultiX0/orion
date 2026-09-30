import 'package:freezed_annotation/freezed_annotation.dart';

import 'tool_call_status.dart';

part 'tool_call.freezed.dart';
part 'tool_call.g.dart';

/// A tool the board asked the PC to run during a turn. Result deltas over the
/// socket carry only id, status and result, so name and args have defaults.
@freezed
abstract class ToolCall with _$ToolCall {
  const factory ToolCall({
    required String id,
    @Default('') String name,
    @Default(<String, dynamic>{}) Map<String, dynamic> args,
    @Default(ToolCallStatus.pending) ToolCallStatus status,
    String? result,
  }) = _ToolCall;

  factory ToolCall.fromJson(Map<String, dynamic> json) =>
      _$ToolCallFromJson(json);
}
