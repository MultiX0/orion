import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/device/data/fake_device_client.dart';
import 'package:orion/features/harness/data/confirmation_queue.dart';
import 'package:orion/features/harness/data/desktop_harness_repository.dart';
import 'package:orion/features/harness/data/dsh/null_runtime.dart';
import 'package:orion/features/harness/data/null_harness_repository.dart';
import 'package:orion/features/harness/data/tool_executor.dart';
import 'package:orion/features/harness/data/tool_log.dart';
import 'package:orion/features/harness/domain/approval_mode.dart';
import 'package:orion/features/harness/domain/harness_call_status.dart';
import 'package:orion/features/harness/domain/tool_request.dart';
import 'package:orion/features/providers/data/fake_provider_repository.dart';
import 'package:orion/features/providers/domain/provider_presets.dart';

import '../../../tool/mock_device/board.dart';
import '../../../tool/mock_device/tool_script.dart';
import '../../support/stub_tools.dart';

void main() {
  late StubTools tools;
  late ConfirmationQueue queue;
  late FakeDeviceClient device;
  late DesktopHarnessRepository repo;
  late Directory temp;
  late List<ApprovalMode> saved;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('orion_approval');
    tools = StubTools();
    queue = ConfirmationQueue(timeout: const Duration(seconds: 5));
    device = FakeDeviceClient(autoTurns: false);
    saved = <ApprovalMode>[];
    late DesktopHarnessRepository created;
    created = DesktopHarnessRepository(
      executor: ToolExecutor(
        tools: tools,
        agent: const NullRuntime(),
        queue: queue,
        brain: () async => (ProviderPresets.deepinfra, 'some-model'),
        localApproval: () => created.approvalMode,
        describe: FakeProviderRepository(),
        onUpdate: (call) => created.record(call),
        onAgentLog: (jobId, line) => created.recordAgentLog(jobId, line),
      ),
      queue: queue,
      agent: const NullRuntime(),
      deviceClient: device,
      log: ToolLog('${temp.path}/tools.jsonl'),
      pairingToken: 'approval-token',
      saveApprovalMode: (mode) async => saved.add(mode),
      port: 0,
    );
    repo = created;
  });

  tearDown(() async {
    await repo.dispose();
    device.dispose();
    try {
      await temp.delete(recursive: true);
    } on FileSystemException {
      return; // Windows can still hold the log file open. Temp, so harmless.
    }
  });

  test('ask keeps lock_pc waiting for the user', () async {
    final call = await repo.executor.start(
      const ToolRequest(callId: 'c1', name: 'lock_pc'),
    );
    expect(call.status, HarnessCallStatus.pendingConfirmation);
    expect(call.approvalMode, ApprovalMode.ask);
    expect(tools.calls, isEmpty);
    queue.denyAll();
  });

  test('auto from the board runs it at once, logged as policy', () async {
    final call = await repo.executor.start(
      const ToolRequest(
        callId: 'c2',
        name: 'lock_pc',
        approval: ApprovalMode.auto,
      ),
    );
    expect(call.status, HarnessCallStatus.done);
    expect(call.approvedBy, 'policy');
    expect(tools.calls, contains('lockPc'));
  });

  test('auto runs an agent task without asking either', () async {
    final call = await repo.executor.start(
      const ToolRequest(
        callId: 'c3',
        name: 'agent_task',
        args: <String, dynamic>{'task': 'tidy the desktop'},
        approval: ApprovalMode.auto,
      ),
    );
    // No dsh in a test, so it fails on the brain, not on a confirmation.
    expect(call.status, isNot(HarnessCallStatus.pendingConfirmation));
    expect(call.approvedBy, 'policy');
  });

  test('a call with no approval field falls back to the local copy', () async {
    await repo.setApprovalMode(ApprovalMode.auto);
    final call = await repo.executor.start(
      const ToolRequest(callId: 'c4', name: 'lock_pc'),
    );
    expect(call.approvalMode, ApprovalMode.auto);
    expect(call.status, HarnessCallStatus.done);
  });

  test('setting the mode writes the board and the local copy', () async {
    final result = await repo.setApprovalMode(ApprovalMode.auto);
    expect(result.isOk, isTrue);
    expect(saved, <ApprovalMode>[ApprovalMode.auto]);
    final config = (await device.config()).getOrThrow();
    expect(config.pc?.approval, ApprovalMode.auto);
    // The patch must not switch PC control off on its way past.
    expect(config.pc?.isEnabled, isFalse);
  });

  test('the board wins: its config overwrites the copy at startup', () async {
    await device.updateConfig(
      (await device.config()).getOrThrow().copyWith(
        pc: (await device.config()).getOrThrow().pc?.copyWith(
          approval: ApprovalMode.auto,
        ),
      ),
    );
    await repo.loadApprovalFromBoard();
    expect(repo.approvalMode, ApprovalMode.auto);
    expect(saved, contains(ApprovalMode.auto));
  });

  test('a call under a new mode moves the header and the copy', () async {
    await repo.executor.start(
      const ToolRequest(
        callId: 'c5',
        name: 'system_stats',
        approval: ApprovalMode.auto,
      ),
    );
    expect(repo.approvalMode, ApprovalMode.auto);
    expect(saved, contains(ApprovalMode.auto));
  });

  test('the log says which mode every call ran under', () async {
    await repo.executor.start(
      const ToolRequest(
        callId: 'c6',
        name: 'system_stats',
        approval: ApprovalMode.auto,
      ),
    );
    // The log is written without being awaited, so give it a moment.
    final file = File('${temp.path}/tools.jsonl');
    for (var i = 0; i < 40 && !file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    final last =
        jsonDecode((await file.readAsLines()).last) as Map<String, dynamic>;
    expect(last['approval'], 'auto');
    expect(last['approved_by'], 'policy');
  });

  test('a phone has no server but still sets the board', () async {
    final phone = NullHarnessRepository(
      deviceClient: device,
      saveApprovalMode: (mode) async => saved.add(mode),
    );
    expect((await phone.setApprovalMode(ApprovalMode.auto)).isOk, isTrue);
    expect(
      (await device.config()).getOrThrow().pc?.approval,
      ApprovalMode.auto,
    );
    expect((await phone.setEnabled(true)).isErr, isTrue);
  });

  group('by voice, on the board', () {
    test('the two phrases map to a mode', () {
      expect(ToolScript.approvalFromText('Orion, ask me first'), 'ask');
      expect(
        ToolScript.approvalFromText('from now on, act on your own'),
        'auto',
      );
      expect(ToolScript.approvalFromText('what is the weather'), isNull);
    });

    test(
      'a turn with the phrase changes the config and says so',
      () async {
        final board = MockBoard();
        final replies = <String>[];
        board.events
            .where((e) => e['type'] == 'turn.reply')
            .listen((e) => replies.add('${e['text']}'));
        await board.runTurn(
          't_1',
          source: 'app',
          text: 'act on your own from now on',
        );
        final pc = board.config['pc']! as Map<String, dynamic>;
        expect(pc['approval'], 'auto');
        expect(replies.single, contains('act on my own'));
        await board.dispose();
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });
}
