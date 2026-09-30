import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../features/device/domain/connection_status.dart';

typedef SocketFactory = WebSocketChannel Function(Uri uri);

/// A socket that comes back on its own. Backoff is 1, 2, 4, 8 seconds, capped
/// at 15, and only resets once a link has held for a while, so a board that
/// flaps every second is not hammered.
///
/// Three things break a link in practice and each has its own answer here:
/// the board reboots, which closes the socket and starts the backoff; Wi-Fi
/// drops, which fails the connect and does the same; and the phone sleeps,
/// which freezes every timer and leaves a socket that looks open and is not.
/// Sleep is caught by the wall clock jumping, not by waiting for silence.
class ReconnectingSocket {
  ReconnectingSocket({
    required this.uriOf,
    SocketFactory? connect,
    this.pingEvery = const Duration(seconds: 10),
    this.silenceLimit = const Duration(seconds: 25),
    this.stableAfter = const Duration(seconds: 10),
    this.suspendTick = const Duration(seconds: 2),
    this.suspendSlack = const Duration(seconds: 5),
    DateTime Function()? clock,
  }) : _connect = connect ?? WebSocketChannel.connect,
       _now = clock ?? DateTime.now;

  /// Asked again on every attempt, so a token that arrives late still lands
  /// on the query string.
  final Uri Function() uriOf;
  final SocketFactory _connect;
  final Duration pingEvery;

  /// The board talks at least every 5 seconds and answers pings. Silence
  /// longer than this means the link is dead even though the socket still
  /// looks open, which is what a phone waking from sleep sees.
  final Duration silenceLimit;

  /// A link that holds this long counts as healthy and resets the backoff.
  final Duration stableAfter;

  /// How often the wall clock is checked, and how much lateness is normal.
  /// A gap bigger than tick plus slack means the process was suspended.
  final Duration suspendTick;
  final Duration suspendSlack;

  final DateTime Function() _now;

  static const _backoff = <int>[1, 2, 4, 8, 15];

  final _messages = StreamController<String>.broadcast();
  final _status = StreamController<ConnectionStatus>.broadcast();

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  Timer? _ping;
  Timer? _watchdog;
  Timer? _stable;
  Timer? _suspendWatch;
  DateTime? _lastTick;
  var _attempt = 0;
  var _wanted = false;
  var _current = ConnectionStatus.disconnected;

  Stream<String> get messages => _messages.stream;
  Stream<ConnectionStatus> get status => _status.stream;
  ConnectionStatus get current => _current;

  Future<void> start() async {
    if (_wanted) return;
    _wanted = true;
    _watchForSuspend();
    await _open();
  }

  /// Stops waiting and tries right now. For a Retry button, and for anything
  /// that knows the network just came back.
  Future<void> reconnectNow() async {
    if (!_wanted) return;
    _attempt = 0;
    _retry?.cancel();
    _teardown();
    await _open();
  }

  Future<void> stop() async {
    _wanted = false;
    _retry?.cancel();
    _stable?.cancel();
    _suspendWatch?.cancel();
    _suspendWatch = null;
    _ping?.cancel();
    _watchdog?.cancel();
    await _sub?.cancel();
    _sub = null;
    await _channel?.sink.close();
    _channel = null;
    _set(ConnectionStatus.disconnected);
  }

  Future<void> dispose() async {
    await stop();
    await _messages.close();
    await _status.close();
  }

  Future<void> _open() async {
    if (!_wanted) return;
    _set(
      _attempt == 0
          ? ConnectionStatus.connecting
          : ConnectionStatus.reconnecting,
    );
    try {
      final channel = _connect(uriOf());
      await channel.ready;
      if (!_wanted) {
        await channel.sink.close();
        return;
      }
      _channel = channel;
      _set(ConnectionStatus.connected);
      _stable?.cancel();
      _stable = Timer(stableAfter, () => _attempt = 0);
      _armWatchdog();
      _ping?.cancel();
      _ping = Timer.periodic(pingEvery, (_) => _sendPing());
      _sub = channel.stream.listen(
        _onMessage,
        onDone: () => _drop('socket closed'),
        onError: (Object _) => _drop('socket error'),
        cancelOnError: true,
      );
    } on Object {
      _scheduleRetry();
    }
  }

  void _onMessage(dynamic message) {
    _armWatchdog();
    if (message is String) {
      if (!_messages.isClosed) _messages.add(message);
    } else if (message is List<int>) {
      if (!_messages.isClosed) _messages.add(utf8.decode(message));
    }
  }

  void _sendPing() {
    try {
      _channel?.sink.add(jsonEncode(const <String, String>{'type': 'ping'}));
    } on Object {
      _drop('ping failed');
    }
  }

  void _armWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(silenceLimit, () => _drop('no events'));
  }

  /// The phone slept, or the laptop lid was shut. Every timer froze, so the
  /// socket looks open and is not. Drop it and go straight back, no backoff:
  /// the user is looking at the screen right now.
  void _watchForSuspend() {
    _lastTick = _now();
    _suspendWatch?.cancel();
    _suspendWatch = Timer.periodic(suspendTick, (_) {
      final now = _now();
      final gap = now.difference(_lastTick ?? now);
      _lastTick = now;
      if (gap <= suspendTick + suspendSlack) return;
      if (!_wanted) return;
      unawaited(reconnectNow());
    });
  }

  void _drop(String _) {
    _teardown();
    if (!_wanted) return;
    _scheduleRetry();
  }

  void _teardown() {
    _ping?.cancel();
    _watchdog?.cancel();
    _stable?.cancel();
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(_channel?.sink.close());
    _channel = null;
  }

  void _scheduleRetry() {
    _set(ConnectionStatus.reconnecting);
    final seconds = _backoff[_attempt.clamp(0, _backoff.length - 1)];
    _attempt++;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: seconds), _open);
  }

  void _set(ConnectionStatus next) {
    if (_current == next) return;
    _current = next;
    if (!_status.isClosed) _status.add(next);
  }
}
