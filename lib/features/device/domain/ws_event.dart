import 'package:freezed_annotation/freezed_annotation.dart';

import '../../conversation/domain/tool_call.dart';
import '../../conversation/domain/turn_timings.dart';
import 'device_mode.dart';
import 'turn_source.dart';

part 'ws_event.freezed.dart';
part 'ws_event.g.dart';

/// Everything the board pushes over /ws. The JSON "type" field picks the case.
@Freezed(unionKey: 'type')
sealed class WsEvent with _$WsEvent {
  /// Full state on connect, then deltas. Null fields did not change.
  @FreezedUnionValue('state')
  const factory WsEvent.state({
    DateTime? ts,
    DeviceMode? mode,
    int? wifiRssi,
    int? volume,
    bool? muted,
    bool? wakeWordEnabled,
    double? level,
    String? error,
  }) = WsStateEvent;

  @FreezedUnionValue('turn.start')
  const factory WsEvent.turnStart({
    required String turnId,
    DateTime? ts,
    @Default(TurnSource.wake) TurnSource source,
  }) = WsTurnStartEvent;

  @FreezedUnionValue('turn.transcript')
  const factory WsEvent.turnTranscript({
    required String turnId,
    required String text,
    DateTime? ts,
  }) = WsTurnTranscriptEvent;

  @FreezedUnionValue('turn.reply')
  const factory WsEvent.turnReply({
    required String turnId,
    required String text,
    DateTime? ts,
  }) = WsTurnReplyEvent;

  /// Sent twice per call: once pending with name and args, once with the result.
  @FreezedUnionValue('turn.tool')
  const factory WsEvent.turnTool({
    required String turnId,
    @JsonKey(name: 'call') required ToolCall toolCall,
    DateTime? ts,
  }) = WsTurnToolEvent;

  @FreezedUnionValue('tts.start')
  const factory WsEvent.ttsStart({required String turnId, DateTime? ts}) =
      WsTtsStartEvent;

  @FreezedUnionValue('tts.end')
  const factory WsEvent.ttsEnd({required String turnId, DateTime? ts}) =
      WsTtsEndEvent;

  @FreezedUnionValue('turn.end')
  const factory WsEvent.turnEnd({
    required String turnId,
    DateTime? ts,
    TurnTimings? timingsMs,
  }) = WsTurnEndEvent;

  @FreezedUnionValue('error')
  const factory WsEvent.error({
    required String code,
    required String message,
    DateTime? ts,
  }) = WsErrorEvent;

  @FreezedUnionValue('log')
  const factory WsEvent.log({
    required String level,
    required String text,
    DateTime? ts,
  }) = WsLogEvent;

  @FreezedUnionValue('pong')
  const factory WsEvent.pong({DateTime? ts}) = WsPongEvent;

  factory WsEvent.fromJson(Map<String, dynamic> json) =>
      _$WsEventFromJson(json);
}
