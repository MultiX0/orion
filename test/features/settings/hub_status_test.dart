import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/settings/domain/hub_status.dart';

void main() {
  test('reads a board that found two hubs', () {
    final s = HubStatus.fromBoard({
      'state': 'found',
      'paired': false,
      'found': [
        {'name': 'Orion Hub on nas', 'url': 'http://192.168.1.5:8780'},
        {'name': 'Garage', 'url': 'http://192.168.1.9:8780'},
        {'name': 'broken'},
        'not a map',
      ],
    });
    expect(s.state, 'found');
    expect(s.paired, isFalse);
    expect(s.found.map((h) => h.name), ['Orion Hub on nas', 'Garage']);
    expect(s.busy, isFalse);
  });

  test('a board waiting for approval is busy and carries the code', () {
    final s = HubStatus.fromBoard({
      'state': 'waiting',
      'paired': false,
      'name': 'Orion Hub on nas',
      'url': 'http://192.168.1.5:8780',
      'code': '4821',
      'found': <dynamic>[],
    });
    expect(s.busy, isTrue);
    expect(s.code, '4821');
    expect(s.address, '192.168.1.5:8780');
  });

  test('missing fields fall back instead of throwing', () {
    final s = HubStatus.fromBoard(<String, dynamic>{});
    expect(s.state, 'none');
    expect(s.found, isEmpty);
    expect(s.address, isNull);
  });
}
