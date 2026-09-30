import 'dart:async';

import '../../../core/result.dart';
import '../../providers/domain/llm_provider.dart';
import '../../providers/domain/provider_repository.dart';
import '../domain/agent_runtime.dart';
import '../domain/approval_mode.dart';
import '../domain/file_hit.dart';
import '../domain/harness_call.dart';
import '../domain/harness_call_status.dart';
import '../domain/media_action.dart';
import '../domain/native_tools.dart';
import '../domain/tool_catalog.dart';
import '../domain/tool_request.dart';
import '../domain/tool_safety.dart';
import '../domain/tool_spec.dart';
import 'confirmation_queue.dart';
import 'native_tools/desktop_control.dart';

/// Which provider and model the harness borrows for screenshots and agent
/// tasks. Null when nothing is configured yet.
typedef BrainLookup = Future<(LlmProvider, String)?> Function();

/// Runs one tool call and reports every status change. Confirmation, the
/// agent and the OS all land here; nothing above this knows the difference.
class ToolExecutor {
  ToolExecutor({
    required this.tools,
    required this.agent,
    required this.queue,
    required this.brain,
    required this.localApproval,
    required this.describe,
    required this.onUpdate,
    required this.onAgentLog,
    this.control,
  });

  final NativeTools tools;
  final AgentRuntime agent;
  final ConfirmationQueue queue;
  final BrainLookup brain;

  /// The desktop's copy of pc.approval, used when the board sends no field.
  final ApprovalMode Function() localApproval;
  final ProviderRepository describe;

  /// Called on every status change, including the first.
  final void Function(HarnessCall call) onUpdate;

  /// One line of agent output, with the job it belongs to.
  final void Function(String jobId, String line) onAgentLog;

  /// Real control of any app. Null where the OS gives no way in, and in tests.
  final DesktopControl? control;

  /// The tools this machine can actually offer right now.
  Future<List<ToolSpec>> catalog() async => ToolCatalog.available(
    hasNativeTools: tools.isSupported,
    hasAgent: await agent.isAvailable(),
    hasControl: control != null,
  );

  /// Answers as soon as it knows: done, error, denied, pending_confirmation
  /// or running. Anything slower keeps going and reports through onUpdate.
  Future<HarnessCall> start(ToolRequest request) async {
    final mode = request.approval ?? localApproval();
    var call = HarnessCall(
      callId: request.callId,
      turnId: request.turnId,
      name: request.name,
      args: request.args,
      receivedAt: DateTime.now(),
      approvalMode: mode,
    );
    final spec = ToolCatalog.byName(request.name);
    if (spec == null) {
      return _push(_error('No tool called ${request.name}', from: call));
    }
    // Act on your own: everything runs the moment it arrives, agent tasks
    // included. The log still records every call and who let it through.
    if (mode == ApprovalMode.auto) {
      return _runAndReport(_push(call.copyWith(approvedBy: 'policy')));
    }
    if (queue.isPreApproved(spec.safety, spec.name)) {
      call = _push(call.copyWith(approvedBy: 'session'));
      return _runAndReport(call);
    }
    final confirmId = 'k${request.callId}';
    call = _push(
      call.copyWith(
        status: HarnessCallStatus.pendingConfirmation,
        confirmId: confirmId,
      ),
    );
    unawaited(_awaitVerdict(call, spec.name));
    return call;
  }

  Future<void> _awaitVerdict(HarnessCall call, String toolName) async {
    final verdict = await queue.ask(
      call,
      canAlwaysAllow: ToolCatalog.byName(toolName)?.safety != ToolSafety.always,
    );
    if (verdict == Verdict.denied) {
      _push(
        call.copyWith(
          status: HarnessCallStatus.denied,
          message: 'denied by user',
          confirmId: null,
        ),
      );
      return;
    }
    await _runAndReport(
      _push(
        call.copyWith(
          status: HarnessCallStatus.pending,
          approvedBy: 'user',
          confirmId: null,
        ),
      ),
    );
  }

  Future<HarnessCall> _runAndReport(HarnessCall call) async {
    try {
      return _push(await _run(call));
    } on NativeToolException catch (e) {
      return _push(_error(e.message, from: call));
    } on Failure catch (e) {
      return _push(_error(e.message, from: call));
    }
  }

  Future<HarnessCall> _run(HarnessCall call) async => switch (call.name) {
    'open_app' => await _openApp(call),
    'lock_pc' => await _lock(call),
    'system_stats' => call.copyWith(
      status: HarnessCallStatus.done,
      result: (await tools.systemStats()).spoken,
    ),
    'screenshot' => await _screenshot(call),
    'search_files' => call.copyWith(
      status: HarnessCallStatus.done,
      result: _hits(await tools.searchFiles(_string(call.args, 'query'))),
    ),
    'media' => await _media(call),
    'agent_task' => await _agentTask(call),
    'open_link' ||
    'close_app' ||
    'ui_look' ||
    'ui_act' ||
    'run_powershell' ||
    'focus_app' ||
    'press_keys' ||
    'type_text' ||
    'open_windows' => await _control(call),
    _ => _error('No tool called ${call.name}', from: call),
  };

  Future<HarnessCall> _control(HarnessCall call) async {
    final c = control;
    if (c == null) return _error('This PC cannot do that', from: call);
    final said = switch (call.name) {
      'open_link' => await c.openLink(_string(call.args, 'target')),
      'close_app' => await c.closeApp(_string(call.args, 'name')),
      'ui_look' => await c.uiLook(_string(call.args, 'app')),
      'ui_act' => await c.uiAct(
        _string(call.args, 'app'),
        _string(call.args, 'control'),
        _string(call.args, 'action'),
        text: _string(call.args, 'text'),
      ),
      'run_powershell' => await c.runPowerShell(_string(call.args, 'command')),
      'focus_app' => await c.focusApp(_string(call.args, 'name')),
      'press_keys' => await c.pressKeys(_string(call.args, 'keys')),
      'type_text' => await c.typeText(
        _string(call.args, 'text'),
        app: _string(call.args, 'app'),
      ),
      _ => (await c.openWindows()).join('\n'),
    };
    return call.copyWith(status: HarnessCallStatus.done, result: said);
  }

  /// Returns once the app's window is there, so the next step does not land
  /// on whatever was in front while it started. Otherwise text meant for
  /// Notepad can go nowhere.
  Future<HarnessCall> _openApp(HarnessCall call) async {
    final name = _string(call.args, 'name');
    final said = await tools.openApp(name);
    final c = control;
    final shown = c == null || await c.waitForWindow(name);
    return call.copyWith(
      status: HarnessCallStatus.done,
      result: shown ? said : '$said, but no window of it has appeared yet',
    );
  }

  Future<HarnessCall> _lock(HarnessCall call) async {
    await tools.lockPc();
    return call.copyWith(
      status: HarnessCallStatus.done,
      result: 'Locked the workstation',
    );
  }

  Future<HarnessCall> _media(HarnessCall call) async {
    final raw = _string(call.args, 'action');
    // The session knows whether anything plays; the keys only toggle.
    const session = {
      'play',
      'pause',
      'play_pause',
      'next',
      'previous',
      'status',
    };
    final c = control;
    if (c != null && session.contains(raw)) {
      final said = await c.media(raw);
      if (said != null) {
        return call.copyWith(status: HarnessCallStatus.done, result: said);
      }
      if (raw == 'status') {
        return call.copyWith(
          status: HarnessCallStatus.done,
          result: 'Nothing is playing.',
        );
      }
    }
    final action = MediaAction.parse(raw);
    if (action == null) {
      return _error('I do not know that media action', from: call);
    }
    await tools.media(action);
    return call.copyWith(
      status: HarnessCallStatus.done,
      result: 'Media: ${action.name}',
    );
  }

  Future<HarnessCall> _screenshot(HarnessCall call) async {
    final png = await tools.screenshot();
    final chosen = await brain();
    if (chosen == null) {
      return _error('No model is set up to look at the screen', from: call);
    }
    final said = await describe.describeImage(
      chosen.$1,
      chosen.$2,
      png,
      'Describe what is on this screen in two sentences.',
    );
    return switch (said) {
      Ok(:final value) => call.copyWith(
        status: HarnessCallStatus.done,
        result: value,
      ),
      Err(:final failure) => _error(failure.message, from: call),
    };
  }

  /// Answers `running` at once, because an agent takes minutes and the
  /// board's turn will not wait.
  Future<HarnessCall> _agentTask(HarnessCall call) async {
    final chosen = await brain();
    if (chosen == null) {
      return _error('No model is set up for the agent', from: call);
    }
    final job = await agent.run(
      _string(call.args, 'task'),
      provider: chosen.$1,
      model: chosen.$2,
    );
    final logs = agent.logs(job.id).listen((line) => onAgentLog(job.id, line));
    unawaited(
      job.done?.then((result) {
        unawaited(logs.cancel());
        _push(
          call.copyWith(
            status: result.ok
                ? HarnessCallStatus.done
                : HarnessCallStatus.error,
            jobId: job.id,
            result: result.ok ? result.text : null,
            message: result.ok ? null : result.text,
          ),
        );
      }),
    );
    return call.copyWith(status: HarnessCallStatus.running, jobId: job.id);
  }

  HarnessCall _push(HarnessCall next) {
    onUpdate(next);
    return next;
  }

  HarnessCall _error(String message, {required HarnessCall from}) =>
      from.copyWith(status: HarnessCallStatus.error, message: message);

  static String _string(Map<String, dynamic> args, String key) =>
      '${args[key] ?? ''}';

  static String _hits(List<FileHit> hits) =>
      hits.isEmpty ? 'Nothing matched' : hits.map((h) => h.name).join(', ');
}
