import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/result.dart';
import '../../domain/board_network.dart';
import '../../domain/join_status.dart';
import 'ble_wire.dart';

// ESP-IDF wifi_constants.proto numbers.
const _stateConnected = 0;
const _stateConnecting = 1;
const _stateDisconnected = 2;
const _stateFailed = 3;
const _reasonAuth = 0;
const _authOpen = 0;

Uint8List encodePairRequest(OrionPairRequest request) =>
    Uint8List.fromList(utf8.encode(jsonEncode(request.toJson())));

/// orion-pair's answer. Anything that is not the documented shape is a
/// protocol failure, never a crash.
Result<OrionPairResponse> parsePairResponse(List<int> bytes) {
  if (bytes.isEmpty) {
    return const Err(
      BluetoothFailure(BluetoothProblem.protocol, 'orion-pair answered empty'),
    );
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  } on FormatException {
    return const Err(ParseFailure('orion-pair did not answer with JSON'));
  }
  if (decoded is! Map<String, dynamic> || decoded['ok'] is! bool) {
    return const Err(ParseFailure('orion-pair answer has no "ok"'));
  }
  for (final key in const ['device_id', 'error', 'message']) {
    final value = decoded[key];
    if (value != null && value is! String) {
      return Err(ParseFailure('orion-pair "$key" is not a string'));
    }
  }
  return Ok(OrionPairResponse.fromJson(decoded));
}

/// The board's station report, in the app's words. ESP-IDF says
/// "disconnected" between retries, so that reads as still connecting until
/// the board runs out of attempts.
JoinStatus joinStatusFrom(BoardWifiReport report) {
  final outOfAttempts = report.attemptsRemaining == 0;
  switch (report.state) {
    case _stateConnected:
      final ip = report.ip;
      if (ip == null || ip.isEmpty) return const JoinStatus.connecting();
      return JoinStatus.connected(ip: ip);
    case _stateFailed:
      return JoinStatus.failed(_reason(report.failReason));
    case _stateConnecting:
    case _stateDisconnected:
      if (outOfAttempts) return JoinStatus.failed(_reason(report.failReason));
      return const JoinStatus.connecting();
    default:
      return const JoinStatus.connecting();
  }
}

// Older ESP-IDF reports every non-auth failure as network not found.
JoinFailure _reason(int? failReason) => failReason == _reasonAuth
    ? JoinFailure.wrongPassword
    : JoinFailure.networkNotFound;

/// The board's scan, tidied for a list: hidden networks out, one row per
/// name at its strongest, strongest first.
List<BoardNetwork> tidyNetworks(Iterable<BoardScanEntry> entries) {
  final best = <String, BoardScanEntry>{};
  for (final entry in entries) {
    final ssid = entry.ssid.trim();
    if (ssid.isEmpty) continue;
    final seen = best[ssid];
    if (seen == null || entry.rssi > seen.rssi) best[ssid] = entry;
  }
  final networks = [
    for (final MapEntry(key: ssid, value: e) in best.entries)
      BoardNetwork(ssid: ssid, rssi: e.rssi, secured: e.auth != _authOpen),
  ];
  networks.sort((a, b) {
    final bySignal = b.rssi.compareTo(a.rssi);
    return bySignal != 0 ? bySignal : a.ssid.compareTo(b.ssid);
  });
  return networks;
}
