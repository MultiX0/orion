import 'package:freezed_annotation/freezed_annotation.dart';

part 'last_exchange.freezed.dart';

/// The two bubbles under the orb.
@freezed
abstract class LastExchange with _$LastExchange {
  const factory LastExchange({
    String? transcript,
    String? reply,

    /// True while the turn is still running.
    @Default(false) bool isLive,
  }) = _LastExchange;
}
