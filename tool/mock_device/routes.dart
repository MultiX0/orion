import 'dart:async';
import 'dart:convert';
import 'dart:io' show stdout;

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'board.dart';
import 'camera.dart';

/// Every REST and WebSocket route from docs/DEVICE_PROTOCOL.md.
class MockRoutes {
  MockRoutes(this.board, this.camera, {this.onSocket});

  final MockBoard board;
  final MockCamera camera;

  /// Lets the server keep track of open sockets so --flaky can drop them.
  final void Function(WebSocketChannel socket)? onSocket;

  late final Handler handler = const Pipeline()
      .addMiddleware(_checkToken)
      .addHandler(_router.call);

  late final Router _router = Router()
    ..get('/api/info', (Request r) => _json(board.info()))
    ..get('/api/state', (Request r) => _json(board.state()))
    ..get('/api/config', (Request r) => _json(_masked(board.config)))
    ..post('/api/config', _postConfig)
    ..post('/api/config/test', _testConfig)
    ..post('/api/provision', _provision)
    ..post('/api/pair', _pair)
    ..post('/api/talk', _talk)
    ..post('/api/talk/snapshot', _talkSnapshot)
    ..post('/api/say', _say)
    ..post('/api/stop', _stop)
    ..get('/api/history', _history)
    ..post('/api/restart', _restart)
    ..get('/capture', (Request r) => camera.capture())
    ..get('/stream', (Request r) => camera.stream())
    ..get('/ws', _ws);

  Future<Response> _postConfig(Request request) async {
    final body = await _body(request);
    if (body == null) return _error(400, 'bad_json', 'Body is not JSON');
    try {
      return _json(_masked(board.mergeConfig(body)));
    } on ConfigRejected catch (e) {
      return _error(400, 'invalid_config', e.message);
    }
  }

  Future<Response> _testConfig(Request request) async {
    if (board.configVersion1) {
      return _error(404, 'not_found', 'This board has no config test');
    }
    final body = await _body(request);
    final stage = body?['stage'];
    if (stage != 'llm' && stage != 'stt' && stage != 'tts') {
      return _error(400, 'bad_request', 'stage is llm, stt or tts');
    }
    // About as long as the smallest real request takes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final result = board.testStage(stage as String);
    // A board in a turn answers 409 and the app tries again.
    if (result['error'] == 'busy') {
      return Response(
        409,
        body: jsonEncode(result),
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    return _json(result);
  }

  Future<Response> _provision(Request request) async {
    final body = await _body(request);
    if (body == null) return _error(400, 'bad_json', 'Body is not JSON');
    final token = body['app_token'];
    if (token is! String || token.isEmpty) {
      return _error(400, 'bad_request', 'app_token is required');
    }
    board.appToken = token;
    final name = body['device_name'];
    if (name is String && name.isNotEmpty) board.config['device_name'] = name;
    return _json(<String, dynamic>{'device_id': board.deviceId, 'ok': true});
  }

  /// Pairing with the code on the screen. The mock has no screen, so its code
  /// is always 123456 and it says so on its console.
  Future<Response> _pair(Request request) async {
    final body = await _body(request);
    final token = body?['app_token'];
    if (token is! String || token.length < 8) {
      return _error(400, 'bad_request', 'app_token 8 to 64 chars');
    }
    final code = body?['code'];
    if (code == null) {
      stdout.writeln('pairing code on screen: 123456');
      return Response(
        202,
        body: jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'code_required',
          'expires_s': 120,
        }),
        headers: const {'content-type': 'application/json'},
      );
    }
    if (code != '123456') {
      return Response(
        403,
        body: jsonEncode(<String, dynamic>{
          'ok': false,
          'error': 'bad_code',
          'left': 4,
          'message': "That is not the code on Orion's screen. 4 tries left.",
        }),
        headers: const {'content-type': 'application/json'},
      );
    }
    board.appToken = token;
    return _json(<String, dynamic>{'device_id': board.deviceId, 'ok': true});
  }

  Future<Response> _talk(Request request) async {
    final body = await _body(request) ?? <String, dynamic>{};
    final text = body['text'] as String?;
    return _startTurn(source: text == null ? 'button' : 'app', text: text);
  }

  Future<Response> _talkSnapshot(Request request) async {
    final body = await _body(request) ?? <String, dynamic>{};
    return _startTurn(
      source: 'app_snapshot',
      text: body['text'] as String?,
      hadImage: true,
    );
  }

  Response _startTurn({
    required String source,
    String? text,
    bool hadImage = false,
  }) {
    if (board.isTurnRunning) {
      return _error(409, 'busy', 'Orion is in a turn right now');
    }
    final id = board.nextTurnId();
    unawaited(
      board.runTurn(id, source: source, text: text, hadImage: hadImage),
    );
    return _json(<String, dynamic>{'turn_id': id});
  }

  Future<Response> _say(Request request) async {
    final body = await _body(request) ?? <String, dynamic>{};
    final text = body['text'];
    if (text is! String || text.isEmpty) {
      return _error(400, 'bad_request', 'text is required');
    }
    if (board.isTurnRunning) {
      return _error(409, 'busy', 'Orion is in a turn right now');
    }
    unawaited(board.runSay(text));
    return _json(<String, dynamic>{'ok': true});
  }

  Response _stop(Request request) {
    board.stopTurn();
    return _json(<String, dynamic>{'ok': true});
  }

  Response _history(Request request) {
    final query = request.url.queryParameters;
    final limit = int.tryParse(query['limit'] ?? '') ?? 20;
    return _json(board.history(limit: limit, before: query['before']));
  }

  Response _restart(Request request) {
    board.emit(<String, dynamic>{
      'type': 'log',
      'level': 'info',
      'text': 'restarting',
    });
    return _json(<String, dynamic>{'ok': true});
  }

  FutureOr<Response> _ws(Request request) {
    final upgrade = webSocketHandler((WebSocketChannel socket, String? _) {
      onSocket?.call(socket);
      socket.sink.add(jsonEncode(board.fullStateEvent()));
      final sub = board.events.listen(
        (event) => socket.sink.add(jsonEncode(event)),
      );
      socket.stream.listen(
        (message) {
          if (message is String && message.contains('ping')) {
            socket.sink.add(
              jsonEncode(<String, dynamic>{
                'type': 'pong',
                'ts': DateTime.now().toUtc().toIso8601String(),
              }),
            );
          }
        },
        onDone: sub.cancel,
        onError: (Object _) => sub.cancel(),
      );
    });
    return upgrade(request);
  }

  /// The board is open until it has been provisioned. After that every
  /// request needs the token, on the header or on the socket query.
  Handler _checkToken(Handler inner) => (Request request) {
    final expected = board.appToken;
    final path = '/${request.url.path}';
    if (expected == null ||
        path == '/api/provision' ||
        path == '/api/info' ||
        path == '/api/pair') {
      return inner(request);
    }
    final given =
        request.headers['x-orion-token'] ??
        request.url.queryParameters['token'];
    if (given != expected) {
      return _error(401, 'unauthorized', 'Wrong or missing X-Orion-Token');
    }
    return inner(request);
  };

  Future<Map<String, dynamic>?> _body(Request request) async {
    final raw = await request.readAsString();
    if (raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  /// Secrets never leave the board in full, same as the real firmware.
  Map<String, dynamic> _masked(Map<String, dynamic> config) {
    final out = <String, dynamic>{};
    for (final entry in config.entries) {
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        out[entry.key] = <String, dynamic>{
          for (final inner in value.entries)
            inner.key: _isSecret(inner.key)
                ? _mask(inner.value as String?)
                : inner.value,
        };
      } else {
        out[entry.key] = value;
      }
    }
    return out;
  }

  bool _isSecret(String key) => key == 'api_key' || key == 'token';

  String? _mask(String? value) {
    if (value == null || value.isEmpty) return value;
    // The last four characters only, as the contract says.
    if (value.length <= 4) return '...$value';
    return '...${value.substring(value.length - 4)}';
  }

  Response _json(Object body) => Response.ok(
    jsonEncode(body),
    headers: const <String, String>{'content-type': 'application/json'},
  );

  Response _error(int status, String code, String message) => Response(
    status,
    body: jsonEncode(<String, dynamic>{'error': code, 'message': message}),
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
