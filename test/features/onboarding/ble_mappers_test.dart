import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/result.dart';
import 'package:orion/features/onboarding/data/ble/ble_mappers.dart';
import 'package:orion/features/onboarding/data/ble/ble_wire.dart';
import 'package:orion/features/onboarding/domain/join_status.dart';

String _fixture(String name) =>
    File('test/fixtures/ble/$name').readAsStringSync();

String _describe(JoinStatus status) => switch (status) {
  JoinConnecting() => 'connecting',
  JoinConnected(:final ip) => 'connected:$ip',
  JoinFailed(:final reason) => 'failed:${reason.name}',
};

void main() {
  group('orion-pair', () {
    test('the request is the JSON the contract names', () {
      final bytes = encodePairRequest(
        const OrionPairRequest(appToken: 'tok', deviceName: 'Orion'),
      );
      expect(jsonDecode(utf8.decode(bytes)), {
        'app_token': 'tok',
        'device_name': 'Orion',
      });
    });

    test('an ok answer carries the device id', () {
      final result = parsePairResponse(
        utf8.encode(_fixture('orion_pair_ok.json')),
      );
      final value = result.valueOrNull!;
      expect(value.ok, isTrue);
      expect(value.deviceId, 'orion-a1b2');
    });

    test('a refusal keeps the board error and message', () {
      final result = parsePairResponse(
        utf8.encode(_fixture('orion_pair_refused.json')),
      );
      final value = result.valueOrNull!;
      expect(value.ok, isFalse);
      expect(value.error, 'busy');
      expect(value.message, 'Setup mode is closing');
    });

    test('empty, non JSON and wrong types are failures, not crashes', () {
      expect(
        parsePairResponse(const []).failureOrNull,
        isA<BluetoothFailure>(),
      );
      expect(
        parsePairResponse(utf8.encode('not json')).failureOrNull,
        isA<ParseFailure>(),
      );
      expect(
        parsePairResponse(utf8.encode('{"ok":"yes"}')).failureOrNull,
        isA<ParseFailure>(),
      );
      expect(
        parsePairResponse(
          utf8.encode('{"ok":true,"device_id":7}'),
        ).failureOrNull,
        isA<ParseFailure>(),
      );
    });
  });

  test('every recorded status maps the way the fixture says', () {
    final lines = _fixture(
      'wifi_status.jsonl',
    ).split('\n').where((l) => l.trim().isNotEmpty);
    for (final line in lines) {
      final row = jsonDecode(line) as Map<String, dynamic>;
      final report = BoardWifiReport.fromJson(
        row['report'] as Map<String, dynamic>,
      );
      expect(_describe(joinStatusFrom(report)), row['expect'], reason: line);
    }
  });

  test('the scan is tidied: hidden out, one row per name, strongest first', () {
    final raw = (jsonDecode(_fixture('wifi_scan.json')) as List<dynamic>).map(
      (e) => BoardScanEntry.fromJson(e as Map<String, dynamic>),
    );
    final networks = tidyNetworks(raw);

    expect(networks.map((n) => n.ssid), [
      'Hearth',
      'DIRECT-7f-Printer',
      'Kepler Guest',
      'Nebula-2G',
      'Observatory WPA3',
    ]);
    expect(networks.first.rssi, -48);
    expect(networks.first.bars, 3);
    expect(
      networks.firstWhere((n) => n.ssid == 'Kepler Guest').secured,
      isFalse,
    );
    expect(
      networks.firstWhere((n) => n.ssid == 'Observatory WPA3').secured,
      isTrue,
    );
    expect(networks.last.bars, 0);
  });
}
