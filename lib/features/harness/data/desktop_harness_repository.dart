import 'dart:async';

import '../../../core/network/local_address.dart';
import '../../../core/result.dart';
import '../../device/domain/device_client.dart';
import '../../device/domain/device_config.dart';
import '../../device/domain/pc_config.dart';
import '../../providers/domain/llm_provider.dart';
import '../domain/agent_runtime.dart';
import '../domain/confirmation_request.dart';
import '../domain/harness_call.dart';
import '../domain/harness_repository.dart';
import '../domain/harness_status.dart';
import 'confirmation_queue.dart';
import 'pc_brain.dart';
import 'pc_memory.dart';
import 'tool_executor.dart';
import 'tool_log.dart';
import 'tool_server.dart';
import '../domain/approval_mode.dart';

/// The real PC-control layer: server, queue, feed and the line the board
/// needs in its config. Constructing this starts nothing. `setEnabled(true)`
/// does, and only on a desktop the user has opted in on.
class DesktopHarnessRepository implements HarnessRepository {
  DesktopHarnessRepository({
    required this.executor,
    required this.queue,
    required this.agent,
    required this._deviceClient,
    required this.log,
    this._liveClient,
    this.pairingToken,
    this.boardHost,
    this.saveApprovalMode,
    Future<(LlmProvider, String)?> Function()? brain,
    PcMemory? memory,
    Future<List<String>> Function()? desktopState,
    this.allowInbound,
    int port = ToolServer.defaultPort,
  }) {
    final pcBrain = brain == null
        ? null
        : PcBrain(
            brain: brain,
            catalog: executor.catalog,
            runTool: executor.start,
            updates: _updates.stream,
            memory: memory,
            desktopState: desktopState,
          );
    server = ToolServer(
      catalog: executor.catalog,
      start: executor.start,
      lookup: (id) => _calls[id],
      updates: _updates.stream,
      agentLogs: _agentLogs.stream,
      token: () => pairingToken,
      chat: pcBrain?.open,
      port: port,
    );
  }

  final ToolExecutor executor;
  final ConfirmationQueue queue;
  final AgentRuntime agent;
  final DeviceClient _deviceClient;
  final DeviceClient Function()? _liveClient;

  /// The board connection of the moment: it is rebuilt when the pairing
  /// changes, and this repository is not.
  DeviceClient get deviceClient => _liveClient?.call() ?? _deviceClient;
  final ToolLog log;

  /// Where the paired board lives, for working out which of this PC's
  /// addresses it can reach. Null when nothing is paired.
  final String? Function()? boardHost;

  /// Keeps AppSettings.approvalMode in step, for when the board is away.
  final Future<void> Function(ApprovalMode mode)? saveApprovalMode;

  /// Makes sure the board can reach the port through the OS firewall, asking
  /// the user through the OS when needed. False when they said no. Null in
  /// tests and on systems without one to ask.
  final Future<bool> Function(int port)? allowInbound;

  /// The token the board was paired with. Set once the keychain answers;
  /// until then the server refuses every request.
  String? pairingToken;

  late final ToolServer server;

  /// The pc.base_url the board was last told, so the header shows the
  /// address that actually went out, not a guess.
  String? _advertised;

  final _calls = <String, HarnessCall>{};
  final _feed = <HarnessCall>[];
  final _updates = StreamController<HarnessCall>.broadcast();
  final _agentLogs = StreamController<(String, String)>.broadcast();
  final _feedOut = StreamController<List<HarnessCall>>.broadcast();
  final _statusOut = StreamController<HarnessStatus>.broadcast();

  var _status = const HarnessStatus();

  /// What the executor falls back to when a call carries no approval field.
  ApprovalMode get approvalMode => _status.approvalMode;

  /// Called by the executor for every status change.
  void record(HarnessCall call) {
    _calls[call.callId] = call;
    final at = _feed.indexWhere((c) => c.callId == call.callId);
    if (at < 0) {
      _feed.insert(0, call);
    } else {
      _feed[at] = call;
    }
    // A call that arrives under a different mode means the board changed it,
    // by voice or from the phone. The board wins.
    if (call.approvalMode != _status.approvalMode) {
      _set(_status.copyWith(approvalMode: call.approvalMode));
      unawaited(
        saveApprovalMode?.call(call.approvalMode) ?? Future<void>.value(),
      );
    }
    if (!_updates.isClosed) _updates.add(call);
    if (!_feedOut.isClosed) _feedOut.add(List.unmodifiable(_feed));
    unawaited(log.append(call));
  }

  void recordAgentLog(String jobId, String line) {
    if (!_agentLogs.isClosed) _agentLogs.add((jobId, line));
  }

  /// What the board and the app should show right now. Called once at
  /// startup so the Harness screen has dsh and Node before anything runs.
  Future<void> refreshStatus({String? providerName, String? model}) async {
    final versions = await agent.versions();
    _set(
      _status.copyWith(
        isServerRunning: server.isRunning,
        serverAddress: _shownAddress(),
        isDshAvailable: versions.hasDsh,
        dshVersion: versions.dsh,
        nodeVersion: versions.node,
        providerName: providerName ?? _status.providerName,
        model: model ?? _status.model,
      ),
    );
  }

  @override
  Stream<HarnessStatus> get status async* {
    yield _status;
    yield* _statusOut.stream;
  }

  @override
  Stream<List<HarnessCall>> get feed async* {
    yield List.unmodifiable(_feed);
    yield* _feedOut.stream;
  }

  @override
  Stream<List<ConfirmationRequest>> get pending async* {
    yield queue.current;
    yield* queue.pending;
  }

  @override
  Future<Result<void>> setEnabled(bool enabled) async {
    if (enabled) {
      if (pairingToken == null) {
        return const Err(
          AuthFailure('Pair with a board before turning PC control on'),
        );
      }
      try {
        await server.startServer();
      } on Object {
        return Err(
          NetworkFailure(
            'Orion could not open a port for PC control: ports '
            '${server.port} to ${server.port + ToolServer.portSpan - 1} are '
            'all used by other programs. Close one and try again.',
          ),
        );
      }
      // Without this the board cannot reach the PC at all. Windows asks the
      // user once; the rule stays.
      final allow = allowInbound;
      if (allow != null && !await allow(server.boundPort ?? server.port)) {
        return const Err(
          NetworkFailure(
            'Windows is blocking Orion from reaching this PC. Turn PC control '
            'on again and choose Yes in the Windows prompt.',
          ),
        );
      }
    } else {
      queue.denyAll();
      await server.stopServer();
    }
    _set(
      _status.copyWith(
        isEnabled: enabled,
        isServerRunning: server.isRunning,
        serverAddress: _shownAddress(),
      ),
    );
    return _tellBoard(enabled);
  }

  @override
  Future<Result<void>> setApprovalMode(ApprovalMode mode) async {
    _set(_status.copyWith(approvalMode: mode));
    await saveApprovalMode?.call(mode);
    final result = await deviceClient.updateConfig(
      DeviceConfig(pc: PcConfig(approval: mode)),
    );
    // The board is the source of truth, but a board that is asleep must not
    // make the control look broken. The local copy already changed.
    return switch (result) {
      Err(failure: NetworkFailure()) => const Ok(null),
      _ => result.map((_) {}),
    };
  }

  /// The desktop's own copy at startup, without telling the board: the
  /// board is asked next and its answer wins.
  void seedApprovalMode(ApprovalMode mode) =>
      _set(_status.copyWith(approvalMode: mode));

  /// The board's config wins over the local copy. Called at startup, so a
  /// mode set from the phone is already in place before the first tool call.
  Future<void> loadApprovalFromBoard() async {
    final result = await deviceClient.config();
    final mode = result.valueOrNull?.pc?.approval;
    if (mode == null || mode == _status.approvalMode) return;
    _set(_status.copyWith(approvalMode: mode));
    await saveApprovalMode?.call(mode);
  }

  @override
  Future<void> approve(
    String confirmId, {
    bool alwaysAllowThisSession = false,
  }) async =>
      queue.approve(confirmId, alwaysAllowThisSession: alwaysAllowThisSession);

  @override
  Future<void> deny(String confirmId) async => queue.deny(confirmId);

  Future<void> dispose() async {
    await server.stopServer();
    await queue.dispose();
    await _updates.close();
    await _agentLogs.close();
    await _feedOut.close();
    await _statusOut.close();
  }

  /// The board only calls us when its own config says to. A board that is
  /// not there is not an error: the server is up either way.
  Future<Result<void>> _tellBoard(bool enabled) async {
    _advertised = enabled
        ? await LocalAddress.baseUrlFor(
            port: server.boundPort ?? server.port,
            boardHost: boardHost?.call(),
          )
        : null;
    _set(_status.copyWith(serverAddress: _shownAddress()));
    final result = await deviceClient.updateConfig(
      DeviceConfig(
        pc: PcConfig(
          enabled: enabled,
          baseUrl: _advertised,
          token: enabled ? pairingToken : null,
        ),
      ),
    );
    // An unreachable board must not make the toggle look broken: the server
    // is running either way, and the board reads pc.enabled from its config.
    return switch (result) {
      Err(failure: NetworkFailure()) => const Ok(null),
      _ => result.map((_) {}),
    };
  }

  /// What the header shows: the address the board was told, or the socket's
  /// own address until the board has been told anything.
  String? _shownAddress() {
    if (!server.isRunning) return null;
    final url = _advertised;
    return url == null ? server.address : url.replaceFirst('http://', '');
  }

  void _set(HarnessStatus next) {
    _status = next;
    if (!_statusOut.isClosed) _statusOut.add(next);
  }
}
