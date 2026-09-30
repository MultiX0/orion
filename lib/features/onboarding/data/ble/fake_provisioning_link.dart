import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../../core/result.dart';
import '../../domain/nearby_board.dart';
import 'ble_contract.dart';
import 'ble_wire.dart';
import 'provisioning_link.dart';

/// A board in setup mode that lives in memory, for tests and for desktops
/// with no Bluetooth. It behaves like the contract says the real one does:
///
/// - the code is [code], anything else is refused;
/// - the password "wrongpass" is turned down by the network;
/// - a name it did not hear is not found, except the hidden [hiddenSsid];
/// - once joined it reports [ip], which on a desktop can be the mock.
class FakeProvisioningLink implements ProvisioningLink {
  FakeProvisioningLink({
    this.code = '123456',
    this.ip = '192.168.1.40',
    this.deviceId = 'orion-a1b2',
    this.hiddenSsid = 'Observatory',
    this.step = const Duration(milliseconds: 700),
    this.pollsBeforeResult = 2,
    List<BoardScanEntry>? networks,
  }) : networks = networks ?? defaultNetworks;

  final String code;
  final String ip;
  final String deviceId;
  final String hiddenSsid;
  final Duration step;
  final int pollsBeforeResult;
  final List<BoardScanEntry> networks;

  /// What the last orion-pair carried, so tests can check the token.
  OrionPairRequest? lastPair;

  /// Everything orion-config has merged, as the board would store it.
  final Map<String, dynamic> config = <String, dynamic>{};

  /// How many orion-config writes arrived, parts included.
  int configWrites = 0;

  /// Set by a test to drop the link on the next status poll.
  bool dropOnNextStatus = false;

  String? _ssid;
  String? _password;
  int _polls = 0;
  bool _open = false;

  static const defaultNetworks = [
    BoardScanEntry(ssid: 'Hearth', rssi: -48, auth: 3, channel: 6),
    BoardScanEntry(ssid: 'Hearth', rssi: -71, auth: 3, channel: 11),
    BoardScanEntry(ssid: 'Kepler Guest', rssi: -63, auth: 0, channel: 1),
    BoardScanEntry(ssid: '', rssi: -66, auth: 3, channel: 6),
    BoardScanEntry(ssid: 'Nebula-2G', rssi: -79, auth: 4, channel: 11),
  ];

  @override
  bool get isSupported => true;

  @override
  bool get isOpen => _open;

  @override
  Stream<NearbyBoard> scan() async* {
    await Future<void>.delayed(step);
    yield const NearbyBoard(
      id: 'AA:BB:CC:00:A1:B2',
      name: 'Orion-a1b2',
      rssi: -58,
    );
    await Future<void>.delayed(step);
    yield const NearbyBoard(
      id: 'AA:BB:CC:00:C3:D4',
      name: 'Orion-c3d4',
      rssi: -77,
    );
    // Advertising goes on until the listener stops the scan.
    await Completer<void>().future;
  }

  @override
  Future<void> open(NearbyBoard board, {required String pop}) async {
    await Future<void>.delayed(step);
    if (pop != code) {
      throw const BluetoothFailure(
        BluetoothProblem.wrongCode,
        'Security1 device verification failed.',
      );
    }
    _open = true;
  }

  @override
  Future<List<BoardScanEntry>> scanNetworks() async {
    _ensureOpen();
    await Future<void>.delayed(step * 2);
    return networks;
  }

  @override
  Future<Uint8List> exchange(String endpoint, Uint8List request) async {
    _ensureOpen();
    if (endpoint == BleContract.configEndpoint) return _config(request);
    if (endpoint != BleContract.pairEndpoint) {
      throw BluetoothFailure(
        BluetoothProblem.protocol,
        'Endpoint "$endpoint" characteristic not found.',
      );
    }
    final json = jsonDecode(utf8.decode(request)) as Map<String, dynamic>;
    lastPair = OrionPairRequest.fromJson(json);
    final answer = {'device_id': deviceId, 'ok': true};
    return Uint8List.fromList(utf8.encode(jsonEncode(answer)));
  }

  final _pending = StringBuffer();

  // The board side of orion-config: parts pile up, the last one merges.
  Uint8List _config(Uint8List request) {
    configWrites++;
    final json = jsonDecode(utf8.decode(request)) as Map<String, dynamic>;
    Map<String, dynamic>? patch;
    if (json['parts'] is int) {
      final part = json['part'] as int;
      if (part == 1) _pending.clear();
      _pending.write(json['data'] as String);
      if (part < (json['parts'] as int)) {
        return _json({'ok': true, 'part': part});
      }
      patch = jsonDecode(_pending.toString()) as Map<String, dynamic>;
    } else {
      patch = json;
    }
    for (final MapEntry(:key, :value) in patch.entries) {
      final current = config[key];
      if (current is Map<String, dynamic> && value is Map<String, dynamic>) {
        current.addAll(value);
      } else {
        config[key] = value is Map<String, dynamic> ? {...value} : value;
      }
    }
    return _json(_masked(config));
  }

  Map<String, dynamic> _masked(Map<String, dynamic> source) => {
    for (final MapEntry(:key, :value) in source.entries)
      key: value is Map<String, dynamic>
          ? _masked(value)
          : (key == 'api_key' && value is String && value.length > 4
                ? '...${value.substring(value.length - 4)}'
                : value),
  };

  Uint8List _json(Object value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  @override
  Future<void> applyCredentials({
    required String ssid,
    required String password,
  }) async {
    _ensureOpen();
    _ssid = ssid;
    _password = password;
    _polls = 0;
  }

  @override
  Future<BoardWifiReport> wifiStatus() async {
    _ensureOpen();
    if (dropOnNextStatus) {
      dropOnNextStatus = false;
      _open = false;
      throw const BluetoothFailure(BluetoothProblem.lostBoard, 'Link dropped');
    }
    _polls++;
    if (_polls <= pollsBeforeResult) return const BoardWifiReport(state: 1);
    final heard = _ssid == hiddenSsid || networks.any((n) => n.ssid == _ssid);
    if (!heard) {
      return const BoardWifiReport(state: 3, failReason: 1);
    }
    if (_password == 'wrongpass') {
      return const BoardWifiReport(state: 3, failReason: 0);
    }
    return BoardWifiReport(state: 0, ip: ip);
  }

  @override
  Future<void> close() async => _open = false;

  void _ensureOpen() {
    if (!_open) {
      throw const BluetoothFailure(
        BluetoothProblem.lostBoard,
        'The Bluetooth link to Orion is closed',
      );
    }
  }
}
