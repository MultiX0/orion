import 'package:freezed_annotation/freezed_annotation.dart';

part 'nearby_board.freezed.dart';

/// A board in setup mode, seen over Bluetooth. It advertises as
/// `Orion-<last4>` only while its screen shows the six digit code.
@freezed
abstract class NearbyBoard with _$NearbyBoard {
  const NearbyBoard._();

  const factory NearbyBoard({
    /// The platform's Bluetooth id: a MAC on Android, a UUID on iOS.
    required String id,

    /// The advertised name, for example Orion-a1b2.
    required String name,

    /// Signal strength in dBm when the scan reported one.
    int? rssi,
  }) = _NearbyBoard;

  static const namePrefix = 'Orion-';

  /// "a1b2" from "Orion-a1b2". The same four characters end the device id
  /// and the board's .local name.
  String get suffix =>
      name.startsWith(namePrefix) ? name.substring(namePrefix.length) : name;
}
