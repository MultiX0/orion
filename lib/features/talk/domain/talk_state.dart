import 'package:freezed_annotation/freezed_annotation.dart';

part 'talk_state.freezed.dart';

/// Request state for the Talk screen. The turn itself is in LiveTurn.
@freezed
abstract class TalkState with _$TalkState {
  const factory TalkState({
    @Default(false) bool isSending,
    String? activeTurnId,
    String? error,
  }) = _TalkState;
}
