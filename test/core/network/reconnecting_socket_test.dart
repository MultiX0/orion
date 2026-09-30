import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/core/network/reconnecting_socket.dart';
import 'package:orion/features/device/domain/connection_status.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/camera.dart';
import '../../../tool/mock_device/routes.dart';

void main() {
  test(
    'backs off 1, 2 then 4 seconds while the board is missing',
    () async {
      final attempts = <DateTime>[];
      final socket = ReconnectingSocket(
        uriOf: () => Uri.parse('ws://localhost:1/ws'),
        connect: (uri) {
          attempts.add(DateTime.now());
          throw const SocketException('nothing there');
        },
      );

      await socket.start();
      await Future<void>.delayed(const Duration(milliseconds: 3400));
      await socket.dispose();

      expect(attempts, hasLength(3), reason: 'now, plus 1s, plus 2s');
      expect(socket.current, ConnectionStatus.disconnected);
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'comes back after the board drops the socket',
    () async {
      final board = MockBoard();
      final open = <WebSocketChannel>[];
      final routes = MockRoutes(
        board,
        MockCamera(FrameStore(const [])),
        onSocket: open.add,
      );
      final server = await shelf_io.serve(routes.handler, 'localhost', 0);

      final socket = ReconnectingSocket(
        uriOf: () => Uri.parse('ws://localhost:${server.port}/ws'),
      );
      final seen = <ConnectionStatus>[];
      final sub = socket.status.listen(seen.add);

      await socket.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(socket.current, ConnectionStatus.connected);
      expect(open, hasLength(1));

      // What --flaky does, and what a board reboot looks like from here.
      await open.first.sink.close(4001, 'bye');
      await Future<void>.delayed(const Duration(milliseconds: 2500));

      expect(seen, contains(ConnectionStatus.reconnecting));
      expect(socket.current, ConnectionStatus.connected);
      expect(open, hasLength(2), reason: 'the board saw a second connection');

      await sub.cancel();
      await socket.dispose();
      await board.dispose();
      await server.close(force: true);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a phone waking from sleep reconnects at once, without waiting',
    () async {
      final board = MockBoard();
      final open = <WebSocketChannel>[];
      final routes = MockRoutes(
        board,
        MockCamera(FrameStore(const [])),
        onSocket: open.add,
      );
      final server = await shelf_io.serve(routes.handler, 'localhost', 0);

      // The wall clock the socket reads. Jumping it is a phone waking up:
      // every timer froze, and the socket it still holds is dead.
      var now = DateTime(2026, 9, 21, 9);
      final socket = ReconnectingSocket(
        uriOf: () => Uri.parse('ws://localhost:${server.port}/ws'),
        suspendTick: const Duration(milliseconds: 50),
        suspendSlack: const Duration(milliseconds: 50),
        clock: () => now,
      );

      await socket.start();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(open, hasLength(1));

      now = now.add(const Duration(minutes: 20));
      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(open, hasLength(2), reason: 'it did not wait out the silence');
      expect(socket.current, ConnectionStatus.connected);

      await socket.dispose();
      await board.dispose();
      await server.close(force: true);
    },
    timeout: const Timeout(Duration(seconds: 40)),
  );

  test(
    'a link that keeps flapping backs off instead of hammering',
    () async {
      final attempts = <DateTime>[];
      late ReconnectingSocket socket;
      socket = ReconnectingSocket(
        uriOf: () => Uri.parse('ws://localhost:1/ws'),
        // Never healthy, so the backoff never resets.
        stableAfter: const Duration(seconds: 30),
        connect: (uri) {
          attempts.add(DateTime.now());
          final channel = _DeadChannel();
          // Connects, then dies. A board rebooting in a loop, or Wi-Fi on
          // the edge of range.
          Timer(const Duration(milliseconds: 50), channel.die);
          return channel;
        },
      );

      await socket.start();
      await Future<void>.delayed(const Duration(milliseconds: 3600));
      await socket.dispose();

      expect(
        attempts,
        hasLength(3),
        reason: 'first, then 1s, then 2s, not four tries in three seconds',
      );
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );

  test(
    'reconnectNow cuts the wait short',
    () async {
      final attempts = <DateTime>[];
      final socket = ReconnectingSocket(
        uriOf: () => Uri.parse('ws://localhost:1/ws'),
        connect: (uri) {
          attempts.add(DateTime.now());
          throw const SocketException('nothing there');
        },
      );

      await socket.start();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      expect(attempts, hasLength(2));

      await socket.reconnectNow();
      expect(attempts, hasLength(3), reason: 'no waiting for the next slot');

      await socket.dispose();
    },
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

/// A channel that opens and then dies on demand, which is what a board that
/// reboots in a loop looks like from the app.
class _DeadChannel extends StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final _incoming = StreamController<dynamic>();
  final _outgoing = StreamController<dynamic>();

  void die() {
    if (!_incoming.isClosed) unawaited(_incoming.close());
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _Sink(_outgoing);

  @override
  Future<void> get ready async {}

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  void pipe(StreamChannel<dynamic> other) => throw UnimplementedError();
}

class _Sink implements WebSocketSink {
  _Sink(this._controller);

  final StreamController<dynamic> _controller;

  @override
  void add(dynamic data) {}

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      _controller.close();

  @override
  Future<void> get done => _controller.done;
}
