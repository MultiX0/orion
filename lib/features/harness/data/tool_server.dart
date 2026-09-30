import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../domain/harness_call.dart';
import '../domain/tool_request.dart';
import '../domain/tool_spec.dart';

/// The endpoints from docs/HARNESS.md, on 0.0.0.0:7331. The board is the
/// only caller. Everything it needs is behind the paired token.
class ToolServer {
  ToolServer({
    required this.catalog,
    required this.start,
    required this.lookup,
    required this.updates,
    required this.token,
    required this.agentLogs,
    this.chat,
    this.port = 7331,
  });

  static const defaultPort = 7331;

  /// The ports tried in turn when the first is busy. The firewall rule covers
  /// all of them, so moving costs no second Windows prompt.
  static const portSpan = 9;

  final Future<List<ToolSpec>> Function() catalog;
  final Future<HarnessCall> Function(ToolRequest request) start;
  final HarnessCall? Function(String callId) lookup;
  final Stream<HarnessCall> updates;

  /// Lines from the agent, tagged with their job id.
  final Stream<(String jobId, String line)> agentLogs;

  /// The PC brain: an OpenAI style chat request in, the spoken answer out as
  /// SSE. Null when the PC has no model set up, which the board takes as its
  /// cue to answer with its own.
  final Future<Stream<List<int>>?> Function(Map<String, dynamic> body)? chat;

  /// The pairing token. Null means nothing is paired yet, and then the
  /// server refuses everything: an open port on the LAN is not acceptable.
  final String? Function() token;

  final int port;

  HttpServer? _server;

  bool get isRunning => _server != null;

  /// The port we actually got. Differs from `port` only when it was 0,
  /// which is how the tests get a free one.
  int? get boundPort => _server?.port;

  /// "192.168.1.20:7331" once listening.
  String? get address {
    final server = _server;
    if (server == null) return null;
    return '${server.address.address}:${server.port}';
  }

  /// Binds [port], or the next free one after it. A port held a moment
  /// longer by the server this replaces gets a few short retries first; one
  /// held by another program is left to it. Port 0, in tests, binds any.
  Future<void> startServer() async {
    if (_server != null) return;
    final handler = const Pipeline()
        .addMiddleware(_auth)
        .addHandler(_router.call);
    if (port == 0) {
      _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, 0);
      return;
    }
    Object? last;
    for (var p = port; p < port + portSpan; p++) {
      for (var attempt = 0; attempt < (p == port ? 6 : 1); attempt++) {
        try {
          _server = await shelf_io.serve(handler, InternetAddress.anyIPv4, p);
          return;
        } on SocketException catch (e) {
          last = e;
          if (p == port) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }
    }
    throw SocketException(
      'Ports $port to ${port + portSpan - 1} are all in use: $last',
    );
  }

  Future<void> stopServer() async {
    final server = _server;
    _server = null;
    await server?.close(force: true);
  }

  late final Router _router = Router()
    ..get('/tools', _tools)
    ..post('/tool', _postTool)
    ..get('/tool/<id>', _getTool)
    ..get('/ws', _ws)
    ..post('/v1/chat/completions', _chat);

  Future<Response> _tools(Request request) async => _json(<String, dynamic>{
    'tools': (await catalog()).map((t) => t.toFunctionJson()).toList(),
  });

  Future<Response> _postTool(Request request) async {
    final body = await _body(request);
    if (body == null) return _error(400, 'Body is not JSON');
    final ToolRequest parsed;
    try {
      parsed = ToolRequest.fromJson(body);
    } on Object {
      return _error(400, 'call_id and name are required');
    }
    return _json(outcomeJson(await start(parsed)));
  }

  Response _getTool(Request request, String id) {
    final call = lookup(id);
    if (call == null) return _error(404, 'No call with that id');
    return _json(outcomeJson(call));
  }

  /// The wire shape from docs/HARNESS.md. Null fields are left out, so each
  /// status carries only its own field.
  static Map<String, dynamic> outcomeJson(HarnessCall call) => ToolOutcome(
    status: call.status,
    result: call.result,
    message: call.message,
    confirmId: call.confirmId,
    jobId: call.jobId,
  ).toJson();

  Future<Response> _chat(Request request) async {
    final body = await _body(request);
    if (body == null) return _error(400, 'Body is not JSON');
    final stream = await chat?.call(body);
    if (stream == null) return _error(503, 'No model is set up on this PC');
    return Response.ok(
      stream,
      headers: const <String, String>{
        'content-type': 'text/event-stream',
        'cache-control': 'no-cache',
      },
      // Each delta goes out as it is written, not when the answer is done.
      context: const <String, Object>{'shelf.io.buffer_output': false},
    );
  }

  FutureOr<Response> _ws(Request request) {
    final upgrade = webSocketHandler((WebSocketChannel socket, String? _) {
      final subs = <StreamSubscription<void>>[
        updates.listen(
          (call) => _send(socket, <String, dynamic>{
            'type': 'tool.update',
            'call_id': call.callId,
            ...outcomeJson(call),
          }),
        ),
        agentLogs.listen(
          (entry) => _send(socket, <String, dynamic>{
            'type': 'agent.log',
            'job_id': entry.$1,
            'text': entry.$2,
          }),
        ),
      ];
      socket.stream.listen(
        (_) {},
        onDone: () => _cancelAll(subs),
        onError: (Object _) => _cancelAll(subs),
      );
    });
    return upgrade(request);
  }

  void _send(WebSocketChannel socket, Map<String, dynamic> event) {
    try {
      socket.sink.add(jsonEncode(event));
    } on StateError {
      return; // The board closed the socket mid-write. Nothing to do.
    }
  }

  void _cancelAll(List<StreamSubscription<void>> subs) {
    for (final sub in subs) {
      unawaited(sub.cancel());
    }
  }

  Handler _auth(Handler inner) => (Request request) {
    final expected = token();
    if (expected == null || expected.isEmpty) {
      return _error(401, 'This PC is not paired with a board yet');
    }
    // The board's model client sends the token as a bearer, like any key.
    final bearer = request.headers['authorization'];
    final given =
        request.headers['x-orion-token'] ??
        (bearer != null && bearer.startsWith('Bearer ')
            ? bearer.substring(7)
            : null) ??
        request.url.queryParameters['token'];
    if (given != expected) {
      return _error(401, 'Wrong or missing X-Orion-Token');
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

  Response _json(Object body) => Response.ok(
    jsonEncode(body),
    headers: const <String, String>{'content-type': 'application/json'},
  );

  Response _error(int status, String message) => Response(
    status,
    body: jsonEncode(<String, dynamic>{'status': 'error', 'message': message}),
    headers: const <String, String>{'content-type': 'application/json'},
  );
}
