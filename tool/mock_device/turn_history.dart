/// The mock board's conversation, in memory. Seeded with a few old turns so
/// the Conversation screen has something the first time it opens.
class TurnHistory {
  TurnHistory() {
    _seed();
  }

  /// What the board "hears" and "says" when nothing was typed.
  static const script = <(String, String)>[
    ('what is on my desk', 'A keyboard, a mug, and a very tired cat.'),
    ('what time is it', 'It is ten past nine.'),
    ('open spotify', 'Opening Spotify on your PC.'),
    ('how is the sky tonight', 'Clear. Orion is up in the south east.'),
    ('remind me to stretch', 'I will nudge you in twenty minutes.'),
  ];

  final _turns = <Map<String, dynamic>>[];

  void add(Map<String, dynamic> turn) => _turns.add(turn);

  /// Newest first, with a cursor, the way GET /api/history is specified.
  Map<String, dynamic> page({int limit = 20, String? before}) {
    var turns = _turns.reversed.toList();
    if (before != null) {
      final index = turns.indexWhere((t) => t['id'] == before);
      if (index >= 0) turns = turns.sublist(index + 1);
    }
    final page = turns.take(limit).toList();
    return <String, dynamic>{
      'turns': page,
      'next_before': page.length < turns.length ? page.last['id'] : null,
    };
  }

  void _seed() {
    final now = DateTime.now().toUtc();
    for (var i = 0; i < 3; i++) {
      final line = script[i];
      _turns.add(<String, dynamic>{
        'id': 't_${(40 + i).toString().padLeft(5, '0')}',
        'started_at': now
            .subtract(Duration(minutes: 30 - i * 7))
            .toIso8601String(),
        'transcript': line.$1,
        'reply': line.$2,
        'had_image': i == 0,
        'tool_calls': const <Map<String, dynamic>>[],
        'timings_ms': const <String, dynamic>{
          'stt': 1400,
          'llm': 2100,
          'tts_first_byte': 480,
          'total': 5200,
        },
      });
    }
  }
}
