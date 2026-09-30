import 'dart:convert';
import 'dart:io';

/// What the PC remembers of the conversation, so "play Lifetime by Chris Grey"
/// an hour after "open Spotify" still means Spotify. The board keeps a few
/// turns in RAM and loses them on a reboot; the PC keeps them on disk, with
/// the actions each turn took and when.
class PcMemory {
  PcMemory({File? file, DateTime Function()? now})
    : _file = file ?? File(_defaultPath()),
      _now = now ?? DateTime.now {
    _load();
  }

  final File _file;
  final DateTime Function() _now;
  final List<Map<String, dynamic>> _turns = [];

  static const _keep = 200;

  static String _defaultPath() {
    final base =
        Platform.environment['APPDATA'] ??
        '${Platform.environment['HOME'] ?? '.'}/.config';
    return '$base${Platform.pathSeparator}Orion${Platform.pathSeparator}pc_memory.json';
  }

  void _load() {
    try {
      final data = jsonDecode(_file.readAsStringSync());
      if (data is List) _turns.addAll(data.cast<Map<String, dynamic>>());
    } on Object {
      // First run, or a file from an older build: start empty.
    }
  }

  /// One finished turn. [actions] are lines like "open_app {name: Spotify}:
  /// Opened Spotify".
  /// [calls] are the same actions as tool calls, `{name, args, result}`,
  /// replayed as such. [model] is kept for whoever reads the file: which
  /// model did the turn.
  void addTurn(
    String user,
    String answer,
    List<String> actions, {
    List<Map<String, dynamic>> calls = const [],
    String? model,
  }) {
    if (user.trim().isEmpty && answer.trim().isEmpty) return;
    _turns.add(<String, dynamic>{
      'at': _now().toIso8601String(),
      'user': user,
      'answer': answer,
      if (actions.isNotEmpty) 'actions': actions,
      if (calls.isNotEmpty) 'calls': calls,
      'model': ?model,
    });
    if (_turns.length > _keep) _turns.removeRange(0, _turns.length - _keep);
    try {
      _file.parent.createSync(recursive: true);
      _file.writeAsStringSync(jsonEncode(_turns));
    } on Object {
      // Memory is a help, never a reason for a turn to fail.
    }
  }

  List<Map<String, dynamic>> _recent(Duration within, int max) {
    final since = _now().subtract(within);
    final hits = _turns
        .where((t) => DateTime.tryParse('${t['at']}')?.isAfter(since) ?? false)
        .toList();
    return hits.length > max ? hits.sublist(hits.length - max) : hits;
  }

  /// The conversation so far as chat messages, oldest first. A turn that
  /// acted comes back with its tool calls and their results, the way it
  /// happened. Replayed as words alone, "Close Chrome." then "Closed
  /// Chrome.", it teaches the model that saying so is the whole answer, and
  /// next time it says it without closing anything. Calls to tools not in
  /// [known] (renamed or removed since) are left out.
  List<Map<String, dynamic>> history({
    Duration within = const Duration(hours: 12),
    int max = 10,
    Set<String>? known,
  }) {
    final out = <Map<String, dynamic>>[];
    for (final (i, t) in _recent(within, max).indexed) {
      out.add(<String, dynamic>{'role': 'user', 'content': '${t['user']}'});
      final calls = [
        for (final c in (t['calls'] as List?) ?? const [])
          if (c is Map && (known == null || known.contains('${c['name']}'))) c,
      ];
      if (calls.isNotEmpty) {
        out.add(<String, dynamic>{
          'role': 'assistant',
          'content': null,
          'tool_calls': [
            for (final (j, c) in calls.indexed)
              <String, dynamic>{
                'id': 'past_${i}_$j',
                'type': 'function',
                'function': <String, dynamic>{
                  'name': '${c['name']}',
                  'arguments': jsonEncode(c['args'] ?? const {}),
                },
              },
          ],
        });
        for (final (j, c) in calls.indexed) {
          out.add(<String, dynamic>{
            'role': 'tool',
            'tool_call_id': 'past_${i}_$j',
            'content': '${c['result'] ?? ''}',
          });
        }
      }
      out.add(<String, dynamic>{
        'role': 'assistant',
        'content': '${t['answer']}',
      });
    }
    return out;
  }

  /// "4 minutes ago: open_app {name: Spotify}: Opened Spotify", newest last.
  String recentActions({Duration within = const Duration(hours: 6)}) {
    final now = _now();
    final lines = <String>[];
    for (final t in _recent(within, 30)) {
      final at = DateTime.tryParse('${t['at']}');
      if (at == null) continue;
      for (final a in (t['actions'] as List?) ?? const []) {
        lines.add('${_ago(now.difference(at))}: $a');
      }
    }
    return lines.length > 12
        ? lines.sublist(lines.length - 12).join('\n')
        : lines.join('\n');
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} minutes ago';
    return '${d.inHours} hours ago';
  }
}
