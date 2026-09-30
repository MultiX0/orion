import 'dart:async';

/// Runs at most `limit` futures at a time. A subnet sweep is 253 knocks per
/// interface; without a cap the socket table fills and every probe times out.
class TaskPool {
  TaskPool(this.limit) : assert(limit > 0, 'limit must be positive');

  final int limit;
  final _waiting = <Completer<void>>[];
  var _active = 0;

  int get active => _active;

  Future<T> run<T>(Future<T> Function() task) async {
    if (_active >= limit) {
      final slot = Completer<void>();
      _waiting.add(slot);
      await slot.future;
    }
    _active++;
    try {
      return await task();
    } finally {
      _active--;
      if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
    }
  }
}
