import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/time/posix_tz.dart';

void main() {
  test('offsets become the POSIX strings the board takes', () {
    expect(PosixTz.fromOffset(Duration.zero), 'UTC0');
    expect(PosixTz.fromOffset(const Duration(hours: 3)), '<+03>-3');
    expect(
      PosixTz.fromOffset(const Duration(hours: 5, minutes: 30)),
      '<+0530>-5:30',
    );
    expect(PosixTz.fromOffset(const Duration(hours: -4)), '<-04>4');
    expect(
      PosixTz.fromOffset(const Duration(hours: -9, minutes: -30)),
      '<-0930>9:30',
    );
  });

  test('every offset in use survives the round trip', () {
    for (final minutes in PosixTz.offsetsInUse) {
      final offset = Duration(minutes: minutes);
      expect(PosixTz.offsetOf(PosixTz.fromOffset(offset)), offset);
    }
  });

  test('a zone with summer time rules has no single offset', () {
    expect(PosixTz.offsetOf('CET-1CEST,M3.5.0,M10.5.0/3'), isNull);
  });

  test('labels read as people write them', () {
    expect(PosixTz.label(const Duration(hours: 3)), 'UTC+03:00');
    expect(PosixTz.label(const Duration(hours: -4)), 'UTC-04:00');
    expect(PosixTz.label(const Duration(hours: 5, minutes: 45)), 'UTC+05:45');
    expect(PosixTz.label(Duration.zero), 'UTC+00:00');
  });
}
