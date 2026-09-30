import 'dart:async';

import '../domain/confirmation_request.dart';
import '../domain/harness_call.dart';
import '../domain/tool_safety.dart';

/// How a pending call ended.
enum Verdict { approved, denied }

/// Holds the calls waiting for the user and the "always allow" ticks they
/// made this session. Session means until the app quits; nothing is written
/// to disk, so a fresh launch asks again.
class ConfirmationQueue {
  ConfirmationQueue({this.timeout = const Duration(minutes: 5)});

  /// A card nobody touches is a denial, not a call that waits forever.
  final Duration timeout;

  final _pending = <String, _Waiting>{};
  final _allowed = <String>{};
  final _changes = StreamController<List<ConfirmationRequest>>.broadcast();

  Stream<List<ConfirmationRequest>> get pending => _changes.stream;

  List<ConfirmationRequest> get current =>
      _pending.values.map((w) => w.request).toList();

  Set<String> get allowedThisSession => Set.unmodifiable(_allowed);

  /// True when this tool can run without asking again.
  bool isPreApproved(ToolSafety safety, String toolName) => switch (safety) {
    ToolSafety.safe => true,
    ToolSafety.always => false,
    ToolSafety.confirm => _allowed.contains(toolName),
  };

  /// Adds a card and hands back the future the executor waits on.
  Future<Verdict> ask(HarnessCall call, {required bool canAlwaysAllow}) {
    final request = ConfirmationRequest(
      id: call.confirmId ?? call.callId,
      toolCall: call,
      requestedAt: DateTime.now(),
      canAlwaysAllow: canAlwaysAllow,
    );
    final waiting = _Waiting(request);
    _pending[request.id] = waiting;
    _emit();
    waiting.timer = Timer(timeout, () => deny(request.id));
    return waiting.verdict.future;
  }

  void approve(String confirmId, {bool alwaysAllowThisSession = false}) {
    final waiting = _pending.remove(confirmId);
    if (waiting == null) return;
    if (alwaysAllowThisSession && waiting.request.canAlwaysAllow) {
      _allowed.add(waiting.request.toolCall.name);
    }
    waiting.settle(Verdict.approved);
    _emit();
  }

  void deny(String confirmId) {
    final waiting = _pending.remove(confirmId);
    if (waiting == null) return;
    waiting.settle(Verdict.denied);
    _emit();
  }

  /// Turning PC control off resolves everything as a denial. Leaving a card
  /// on screen with no server behind it would be a lie.
  void denyAll() {
    for (final id in _pending.keys.toList()) {
      deny(id);
    }
  }

  Future<void> dispose() async {
    denyAll();
    await _changes.close();
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(current);
  }
}

class _Waiting {
  _Waiting(this.request);

  final ConfirmationRequest request;
  final verdict = Completer<Verdict>();
  Timer? timer;

  void settle(Verdict value) {
    timer?.cancel();
    if (!verdict.isCompleted) verdict.complete(value);
  }
}
