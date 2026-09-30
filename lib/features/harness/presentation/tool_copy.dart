/// One line per tool, lifted from docs/HARNESS.md, so the feed and the
/// confirmation card say what a call does instead of only naming it.
String toolDescription(String name) => switch (name) {
  'open_app' => 'Open an installed application by name',
  'lock_pc' => 'Lock the workstation',
  'system_stats' => 'Read CPU, RAM, GPU usage and temperatures',
  'screenshot' => 'Take a screenshot and describe it',
  'search_files' => 'Find files by name in Documents, Downloads and Desktop',
  'media' => 'Play, pause, skip or change the volume',
  'agent_task' => 'Hand a multi-step task to the PC agent',
  _ => 'A tool the board asked for',
};

/// "name: spotify" lines. The task text is left out on purpose; it is the
/// one argument that deserves body type, see [taskOf].
List<String> argLines(Map<String, dynamic> args) => [
  for (final e in args.entries)
    if (e.key != 'task') '${e.key}: ${e.value}',
];

String? taskOf(Map<String, dynamic> args) {
  final task = args['task'];
  return task is String && task.isNotEmpty ? task : null;
}

/// "15:38:47", local time.
String clock(DateTime t) {
  final l = t.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(l.hour)}:${two(l.minute)}:${two(l.second)}';
}

/// "1.2 s" or "48 s", the way an instrument would print it.
String elapsedLabel(Duration d) {
  final s = d.inMilliseconds / 1000;
  return s < 10 ? '${s.toStringAsFixed(1)} s' : '${s.round()} s';
}

/// How long the board waits on a pending call before it tells the user it
/// started something and moves on. docs/HARNESS.md.
const boardPatience = Duration(seconds: 30);

/// Which mode a call ran under, for the feed. "policy" is the board's
/// act-on-your-own setting; the other two came from a confirmation.
String approvedByLabel(String approvedBy) => switch (approvedBy) {
  'policy' => 'on its own',
  'session' => 'allowed this session',
  'user' => 'approved by you',
  _ => approvedBy,
};
