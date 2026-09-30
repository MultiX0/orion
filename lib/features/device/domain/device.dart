import 'package:freezed_annotation/freezed_annotation.dart';

part 'device.freezed.dart';
part 'device.g.dart';

/// A board the app found or paired with. host is an ip, or host:port.
@freezed
abstract class Device with _$Device {
  const factory Device({
    required String id,
    required String name,
    required String host,
    String? fwVersion,

    /// How discovery found it: beacon, mdns, sweep, name, manual. Null when unknown.
    String? source,
  }) = _Device;

  factory Device.fromJson(Map<String, dynamic> json) => _$DeviceFromJson(json);
}
