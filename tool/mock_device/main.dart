import 'dart:async';
import 'dart:io';

import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'beacon.dart';
import 'board.dart';
import 'camera.dart';
import 'harness_client.dart';
import 'routes.dart';

/// The fake Orion board. Run it with:
///   dart run tool/mock_device/main.dart [--port 8080] [--fps 10] [--flaky] [--config-v1]
///
/// Once the desktop app turns PC control on it posts its address and token
/// into config.pc, and from then on the board calls the real harness.
Future<void> main(List<String> args) async {
  final port = _intArg(args, '--port') ?? 8080;
  final fps = _intArg(args, '--fps') ?? 10;
  final flaky = args.contains('--flaky');
  final configV1 = args.contains('--config-v1');

  final frames = FrameStore.fromDirectory(_framesDir());
  if (frames.isEmpty) {
    stderr.writeln('No JPEGs found in tool/mock_device/frames.');
    exitCode = 1;
    return;
  }

  final board = MockBoard(configVersion1: configV1)..start();
  _wireHarness(board);
  final sockets = <WebSocketChannel>[];
  final routes = MockRoutes(
    board,
    MockCamera(frames, fps: fps),
    onSocket: sockets.add,
  );

  final server = await shelf_io.serve(
    routes.handler,
    InternetAddress.anyIPv4,
    port,
  );
  server.autoCompress = true;
  _log('Orion mock board on http://localhost:${server.port}');
  _log('${frames.frames.length} frames, $fps fps${flaky ? ', flaky' : ''}');
  _log(configV1 ? 'config version 1: llm and fish' : 'config version 2');

  final beacon = MockBeacon(
    deviceId: board.deviceId,
    name: '${board.config['device_name']}',
    httpPort: server.port,
  );
  _log(
    await beacon.start()
        ? 'beaconing on udp 7332 every 2s'
        : 'udp 7332 is taken, no beacon',
  );

  if (flaky) {
    Timer.periodic(const Duration(seconds: 20), (_) {
      // 1000 or 3000 to 4999 only, the socket package rejects anything else.
      for (final socket in sockets) {
        unawaited(socket.sink.close(4001, 'flaky'));
      }
      sockets.clear();
      _log('dropped the sockets, reconnect should kick in');
    });
  }

  await ProcessSignal.sigint.watch().first;
  _log('bye');
  beacon.stop();
  await board.dispose();
  await server.close(force: true);
}

/// Points the board's tool calls at whatever config.pc says. A desktop that
/// never turned PC control on leaves base_url null and no tool ever runs.
void _wireHarness(MockBoard board) {
  HarnessClient? clientFor() {
    final pc = board.config['pc']! as Map<String, dynamic>;
    final baseUrl = pc['base_url'];
    if (pc['enabled'] != true || baseUrl is! String || baseUrl.isEmpty) {
      return null;
    }
    return HarnessClient(baseUrl: baseUrl, token: pc['token'] as String?);
  }

  board.availableTools = () async {
    final client = clientFor();
    if (client == null) return <String>{};
    final names = await client.toolNames();
    client.close();
    _log('desktop offers ${names.length} tools');
    return names;
  };

  board.onToolCall = (callId, turnId, name, args, approval, onUpdate) async {
    final client = clientFor();
    if (client == null) {
      return <String, dynamic>{'status': 'error', 'message': 'No PC attached'};
    }
    _log('calling $name on the desktop');
    final outcome = await client.call(
      callId: callId,
      turnId: turnId,
      name: name,
      args: args,
      approval: approval,
      onUpdate: (update) {
        _log('$name is ${update['status']}');
        onUpdate(update);
      },
    );
    client.close();
    return outcome;
  };
}

/// Works both from the repo root and from the tool folder.
Directory _framesDir() {
  final here = Directory('tool/mock_device/frames');
  if (here.existsSync()) return here;
  final beside = Directory.fromUri(Platform.script.resolve('frames'));
  if (beside.existsSync()) return beside;
  return here;
}

int? _intArg(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return int.tryParse(args[index + 1]);
}

// The mock is a CLI, stdout is its whole interface.
void _log(String line) => stdout.writeln('[mock] $line');
