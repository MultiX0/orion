import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The board's half of docs/HARNESS.md. Fetches the tool list at turn start,
/// posts the call, then polls while the desktop waits for the user. Written
/// with dart:io only, because the mock has no package dependencies of its own.
class HarnessClient {
  HarnessClient({required this.baseUrl, required this.token, HttpClient? http})
    : _http = http ?? HttpClient();

  /// For example http://192.168.1.20:7331, straight from config.pc.base_url.
  final String baseUrl;
  final String? token;
  final HttpClient _http;

  /// The board's LLM turn waits this long, then says "I started that".
  static const waitLimit = Duration(seconds: 30);

  Future<Set<String>> toolNames() async {
    final body = await _send('GET', '/tools');
    final tools = body?['tools'];
    if (tools is! List) return <String>{};
    return tools
        .whereType<Map<String, dynamic>>()
        .map((t) => t['function'])
        .whereType<Map<String, dynamic>>()
        .map((f) => f['name'])
        .whereType<String>()
        .toSet();
  }

  /// Returns the final outcome, reporting every status change on the way.
  Future<Map<String, dynamic>> call({
    required String callId,
    required String turnId,
    required String name,
    required Map<String, dynamic> args,
    String approval = 'ask',
    void Function(Map<String, dynamic> outcome)? onUpdate,
  }) async {
    var outcome =
        await _send(
          'POST',
          '/tool',
          body: <String, dynamic>{
            'call_id': callId,
            'turn_id': turnId,
            'name': name,
            'args': args,
            'approval': approval,
          },
        ) ??
        _error('The PC did not answer');
    onUpdate?.call(outcome);

    final deadline = DateTime.now().add(waitLimit);
    while (_isOpen(outcome) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final next = await _send('GET', '/tool/$callId');
      if (next == null) break;
      if (next['status'] == outcome['status']) continue;
      outcome = next;
      onUpdate?.call(outcome);
    }
    if (_isOpen(outcome)) {
      return _error('I have started that on the PC');
    }
    return outcome;
  }

  void close() => _http.close(force: true);

  static bool _isOpen(Map<String, dynamic> outcome) =>
      outcome['status'] == 'pending_confirmation' ||
      outcome['status'] == 'running';

  Future<Map<String, dynamic>?> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    try {
      final request = await _http.openUrl(method, Uri.parse('$baseUrl$path'));
      final key = token;
      if (key != null) request.headers.set('X-Orion-Token', key);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final text = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(text);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on Object {
      return null; // A desktop that is off is not an error, just no tools.
    }
  }

  static Map<String, dynamic> _error(String message) => <String, dynamic>{
    'status': 'error',
    'message': message,
  };
}
