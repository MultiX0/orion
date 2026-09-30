import 'dart:async';

import '../../../core/result.dart';
import '../domain/confirmation_request.dart';
import '../domain/harness_call.dart';
import '../domain/harness_call_status.dart';
import '../domain/harness_repository.dart';
import '../domain/harness_status.dart';
import '../domain/approval_mode.dart';

/// Invents a tool call every few seconds. Safe ones run at once, the rest
/// wait in the confirmation queue until approved or denied.
class FakeHarnessRepository implements HarnessRepository {
  FakeHarnessRepository({this.autoCalls = true}) {
    if (autoCalls) {
      _timer = Timer.periodic(const Duration(seconds: 12), (_) => _nextCall());
    }
  }

  static const _script = <(String, Map<String, dynamic>, bool, String)>[
    ('open_app', {'name': 'spotify'}, false, 'Opened Spotify'),
    ('system_stats', {}, false, 'CPU 12%, RAM 41%, GPU 8% at 52C'),
    ('lock_pc', {}, true, 'Locked the workstation'),
    (
      'agent_task',
      {'task': 'Find last week\'s invoice PDF in Downloads and open it'},
      true,
      'Opened invoice-2026-09.pdf',
    ),
    ('media', {'action': 'pause'}, false, 'Paused'),
  ];

  final bool autoCalls;
  final _status = _Live(
    const HarnessStatus(
      isEnabled: true,
      isServerRunning: true,
      serverAddress: '192.168.1.20:7331',
      providerName: 'DeepInfra',
      model: 'meta-llama/Llama-3.3-70B-Instruct-Turbo',
    ),
  );
  final _feed = _Live(<HarnessCall>[]);
  final _pending = _Live(<ConfirmationRequest>[]);
  final _sessionAllowed = <String>{};
  Timer? _timer;
  var _counter = 0;

  @override
  Stream<HarnessStatus> get status => _status.stream;

  @override
  Stream<List<HarnessCall>> get feed => _feed.stream;

  @override
  Stream<List<ConfirmationRequest>> get pending => _pending.stream;

  @override
  Future<Result<void>> setEnabled(bool enabled) async {
    _status.value = _status.value.copyWith(
      isEnabled: enabled,
      isServerRunning: enabled,
      serverAddress: enabled ? '192.168.1.20:7331' : null,
    );
    return const Ok(null);
  }

  @override
  Future<Result<void>> setApprovalMode(ApprovalMode mode) async {
    _status.value = _status.value.copyWith(approvalMode: mode);
    return const Ok(null);
  }

  @override
  Future<void> approve(
    String confirmId, {
    bool alwaysAllowThisSession = false,
  }) async {
    final request = _takePending(confirmId);
    if (request == null) return;
    if (alwaysAllowThisSession) _sessionAllowed.add(request.toolCall.name);
    _update(
      request.toolCall.callId,
      (c) => c.copyWith(
        status: HarnessCallStatus.running,
        approvedBy: alwaysAllowThisSession ? 'session' : 'user',
      ),
    );
    unawaited(_complete(request.toolCall.callId));
  }

  @override
  Future<void> deny(String confirmId) async {
    final request = _takePending(confirmId);
    if (request == null) return;
    _update(
      request.toolCall.callId,
      (c) => c.copyWith(
        status: HarnessCallStatus.denied,
        message: 'denied by user',
      ),
    );
  }

  void dispose() {
    _timer?.cancel();
    _status.close();
    _feed.close();
    _pending.close();
  }

  void _nextCall() {
    if (!_status.value.isEnabled) return;
    final (name, args, needsConfirm, _) = _script[_counter % _script.length];
    _counter++;
    final callId = 'c${_counter + 100}';
    final confirm = needsConfirm && !_sessionAllowed.contains(name);
    final call = HarnessCall(
      callId: callId,
      turnId: 't_${(_counter + 60).toString().padLeft(5, '0')}',
      name: name,
      args: args,
      receivedAt: DateTime.now(),
      status: confirm
          ? HarnessCallStatus.pendingConfirmation
          : HarnessCallStatus.running,
      confirmId: confirm ? 'k$_counter' : null,
    );
    _feed.value = [call, ..._feed.value];
    if (confirm) {
      _pending.value = [
        ..._pending.value,
        ConfirmationRequest(
          id: call.confirmId!,
          toolCall: call,
          requestedAt: call.receivedAt,
          canAlwaysAllow: name != 'agent_task',
        ),
      ];
    } else {
      unawaited(_complete(callId));
    }
  }

  Future<void> _complete(String callId) async {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (_feed.isClosed) return;
    final call = _feed.value.where((c) => c.callId == callId).firstOrNull;
    if (call == null) return;
    final line = _script.where((s) => s.$1 == call.name).firstOrNull;
    _update(
      callId,
      (c) =>
          c.copyWith(status: HarnessCallStatus.done, result: line?.$4 ?? 'ok'),
    );
  }

  ConfirmationRequest? _takePending(String confirmId) {
    final request = _pending.value.where((r) => r.id == confirmId).firstOrNull;
    if (request == null) return null;
    _pending.value = _pending.value.where((r) => r.id != confirmId).toList();
    return request;
  }

  void _update(String callId, HarnessCall Function(HarnessCall) change) {
    _feed.value = [
      for (final c in _feed.value) c.callId == callId ? change(c) : c,
    ];
  }
}

/// A value plus a stream that replays it to each new listener.
class _Live<T> {
  _Live(this._value);

  final _controller = StreamController<T>.broadcast();
  T _value;

  T get value => _value;

  set value(T next) {
    _value = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  bool get isClosed => _controller.isClosed;

  Stream<T> get stream async* {
    yield _value;
    yield* _controller.stream;
  }

  void close() => unawaited(_controller.close());
}
