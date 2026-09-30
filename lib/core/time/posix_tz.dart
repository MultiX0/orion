/// Time zones the way the board takes them: POSIX TZ strings. The apps send a
/// fixed offset read from the phone's or the PC's own clock and send it again
/// when that offset changes (summer time), so the board needs no zone
/// database of its own.
abstract final class PosixTz {
  /// "UTC0" for UTC, "<+03>-3" for UTC+3, "<+0530>-5:30" for UTC+5:30,
  /// "<-04>4" for UTC-4. POSIX counts hours west of Greenwich as positive,
  /// hence the flipped sign after the name.
  static String fromOffset(Duration offset) {
    final minutes = offset.inMinutes;
    if (minutes == 0) return 'UTC0';
    final abs = minutes.abs();
    final h = abs ~/ 60;
    final m = abs % 60;
    final mm = m.toString().padLeft(2, '0');
    final name =
        '<${minutes > 0 ? '+' : '-'}${h.toString().padLeft(2, '0')}'
        '${m == 0 ? '' : mm}>';
    return '$name${minutes > 0 ? '-' : ''}$h${m == 0 ? '' : ':$mm'}';
  }

  static final _fixed = RegExp(
    r'^<[+-]\d{2}(\d{2})?>([+-]?)(\d{1,2})(?::(\d{2}))?$',
  );

  /// The offset [tz] stands for when it is a fixed offset like the ones
  /// [fromOffset] makes; null for a zone with summer time rules.
  static Duration? offsetOf(String tz) {
    if (tz == 'UTC0' || tz == 'UTC' || tz == 'GMT0') return Duration.zero;
    final m = _fixed.firstMatch(tz);
    if (m == null) return null;
    final minutes = int.parse(m.group(3)!) * 60 + int.parse(m.group(4) ?? '0');
    // West is positive in POSIX: no sign means west of Greenwich.
    return Duration(minutes: m.group(2) == '-' ? minutes : -minutes);
  }

  /// "UTC+03:00", "UTC-04:00", "UTC+05:30".
  static String label(Duration offset) {
    final minutes = offset.inMinutes;
    final abs = minutes.abs();
    final h = (abs ~/ 60).toString().padLeft(2, '0');
    final m = (abs % 60).toString().padLeft(2, '0');
    return 'UTC${minutes < 0 ? '-' : '+'}$h:$m';
  }

  /// Every offset in use somewhere, west to east, in minutes.
  static const offsetsInUse = <int>[
    -720,
    -660,
    -600,
    -570,
    -540,
    -480,
    -420,
    -360,
    -300,
    -240,
    -210,
    -180,
    -120,
    -60,
    0,
    60,
    120,
    180,
    210,
    240,
    270,
    300,
    330,
    345,
    360,
    390,
    420,
    480,
    525,
    540,
    570,
    600,
    630,
    660,
    720,
    765,
    780,
    840,
  ];
}
