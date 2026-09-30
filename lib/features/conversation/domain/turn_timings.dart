import 'package:freezed_annotation/freezed_annotation.dart';

part 'turn_timings.freezed.dart';
part 'turn_timings.g.dart';

/// Milliseconds per stage of a turn, as the board measured them.
@freezed
abstract class TurnTimings with _$TurnTimings {
  const factory TurnTimings({
    int? stt,
    int? llm,
    int? ttsFirstByte,
    int? total,
  }) = _TurnTimings;

  factory TurnTimings.fromJson(Map<String, dynamic> json) =>
      _$TurnTimingsFromJson(json);
}
