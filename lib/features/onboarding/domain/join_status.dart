import 'package:freezed_annotation/freezed_annotation.dart';

part 'join_status.freezed.dart';

/// Why the board did not join the network.
enum JoinFailure {
  /// The network turned the password down.
  wrongPassword,

  /// No network by that name answered, or it is 5 GHz only.
  networkNotFound,

  /// The Bluetooth link dropped before the board said how it went.
  lostBoard,

  /// The board kept trying and never settled either way.
  timedOut,
}

/// The board's own report while it joins the network, polled over
/// Bluetooth after the credentials are applied.
@freezed
sealed class JoinStatus with _$JoinStatus {
  const factory JoinStatus.connecting() = JoinConnecting;

  const factory JoinStatus.connected({required String ip}) = JoinConnected;

  const factory JoinStatus.failed(JoinFailure reason) = JoinFailed;
}
