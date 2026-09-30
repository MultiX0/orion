import 'package:freezed_annotation/freezed_annotation.dart';

part 'ble_wire.freezed.dart';
part 'ble_wire.g.dart';

/// Written to orion-pair before the credentials.
@freezed
abstract class OrionPairRequest with _$OrionPairRequest {
  const factory OrionPairRequest({
    required String appToken,
    required String deviceName,
  }) = _OrionPairRequest;

  factory OrionPairRequest.fromJson(Map<String, dynamic> json) =>
      _$OrionPairRequestFromJson(json);
}

/// What orion-pair answers. A refusal may carry the board's own error shape.
@freezed
abstract class OrionPairResponse with _$OrionPairResponse {
  const factory OrionPairResponse({
    required bool ok,
    String? deviceId,
    String? error,
    String? message,
  }) = _OrionPairResponse;

  factory OrionPairResponse.fromJson(Map<String, dynamic> json) =>
      _$OrionPairResponseFromJson(json);
}

/// One row of the board's prov-scan result, as ESP-IDF reports it. auth is
/// the WifiAuthMode number: 0 is open, anything else wants a password.
@freezed
abstract class BoardScanEntry with _$BoardScanEntry {
  const factory BoardScanEntry({
    required String ssid,
    required int rssi,
    required int auth,
    @Default(0) int channel,
  }) = _BoardScanEntry;

  factory BoardScanEntry.fromJson(Map<String, dynamic> json) =>
      _$BoardScanEntryFromJson(json);
}

/// The board's prov-config status. state is ESP-IDF's WifiStationState:
/// 0 connected, 1 connecting, 2 disconnected, 3 failed. failReason is
/// WifiConnectFailedReason: 0 auth error, 1 network not found.
@freezed
abstract class BoardWifiReport with _$BoardWifiReport {
  const factory BoardWifiReport({
    required int state,
    int? failReason,
    String? ip,
    int? attemptsRemaining,
  }) = _BoardWifiReport;

  factory BoardWifiReport.fromJson(Map<String, dynamic> json) =>
      _$BoardWifiReportFromJson(json);
}
