/// Runs one tool somewhere else and reports every status change on the way.
typedef ToolRunner =
    Future<Map<String, dynamic>> Function(
      String callId,
      String turnId,
      String name,
      Map<String, dynamic> args,
      String approval,
      void Function(Map<String, dynamic> outcome) onUpdate,
    );

/// One tool the mock board decides to call.
class MockToolCall {
  const MockToolCall(this.name, [this.args = const <String, dynamic>{}]);

  final String name;
  final Map<String, dynamic> args;
}

/// Stands in for the LLM's tool choice. A real board sends the transcript to
/// a model and reads back a function call; the mock matches a few phrases so
/// a demo is repeatable, and otherwise opens an app every third turn.
abstract final class ToolScript {
  /// What the board says once the PC has answered. The tool result is the
  /// interesting part, so it wins over the scripted line.
  static String replyWith(String reply, Map<String, dynamic>? tool) {
    final result = tool?['result'];
    if (result is String && result.isNotEmpty) return result;
    final message = tool?['message'];
    if (message is String && message.isNotEmpty) return message;
    return reply;
  }

  /// The two phrases docs/DEVICE_PROTOCOL.md says a board acts on itself.
  /// Returns the new pc.approval, or null when the turn was about anything
  /// else.
  static String? approvalFromText(String text) {
    final said = text.toLowerCase();
    if (said.contains('ask me first')) return 'ask';
    if (said.contains('act on your own')) return 'auto';
    return null;
  }

  static String approvalReply(String mode) => mode == 'auto'
      ? 'Done. I will act on my own from now on, agent tasks included.'
      : 'Done. I will ask you first from now on.';

  static MockToolCall? forText(
    String text, {
    required bool pcEnabled,
    required int turnCounter,
    required Set<String> available,
  }) {
    if (!pcEnabled || available.isEmpty) return null;
    final chosen = _match(text.toLowerCase()) ?? _every(turnCounter);
    if (chosen == null || !available.contains(chosen.name)) return null;
    return chosen;
  }

  static MockToolCall? _match(String text) {
    final open = RegExp(r'\bopen\s+([a-z0-9 .+-]+)').firstMatch(text);
    if (open != null) {
      return MockToolCall('open_app', <String, dynamic>{
        'name': open.group(1)!.trim(),
      });
    }
    final find = RegExp(
      r'\b(?:find|search for|look for)\s+([a-z0-9 .+-]+)',
    ).firstMatch(text);
    if (find != null) {
      return MockToolCall('search_files', <String, dynamic>{
        'query': find.group(1)!.trim(),
      });
    }
    if (_has(text, <String>['lock', 'lock my pc', 'lock the pc'])) {
      return const MockToolCall('lock_pc');
    }
    if (_has(text, <String>['cpu', 'memory', 'ram', 'gpu', 'temperature'])) {
      return const MockToolCall('system_stats');
    }
    if (_has(text, <String>['screen', 'screenshot', 'what am i looking at'])) {
      return const MockToolCall('screenshot');
    }
    final media = _media(text);
    if (media != null) {
      return MockToolCall('media', <String, dynamic>{'action': media});
    }
    if (_has(text, <String>['clean up', 'tidy', 'organise', 'organize'])) {
      return MockToolCall('agent_task', <String, dynamic>{'task': text});
    }
    return null;
  }

  static String? _media(String text) {
    if (_has(text, <String>['next track', 'skip'])) return 'next';
    if (_has(text, <String>['previous track', 'go back a track'])) {
      return 'previous';
    }
    if (_has(text, <String>['pause'])) return 'pause';
    if (_has(text, <String>['resume', 'play music'])) return 'play';
    if (_has(text, <String>['louder', 'turn it up'])) return 'volume_up';
    if (_has(text, <String>['quieter', 'turn it down'])) return 'volume_down';
    if (_has(text, <String>['mute'])) return 'mute';
    return null;
  }

  /// Nothing matched, so keep the demo lively without being constant.
  static MockToolCall? _every(int turnCounter) => turnCounter % 3 == 0
      ? const MockToolCall('open_app', <String, dynamic>{'name': 'spotify'})
      : null;

  static bool _has(String text, List<String> needles) =>
      needles.any(text.contains);
}
