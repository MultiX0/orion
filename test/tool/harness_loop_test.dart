import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/device/data/fake_device_client.dart';
import 'package:orion/features/harness/data/confirmation_queue.dart';
import 'package:orion/features/harness/data/desktop_harness_repository.dart';
import 'package:orion/features/harness/data/dsh/null_runtime.dart';
import 'package:orion/features/harness/data/tool_executor.dart';
import 'package:orion/features/harness/data/tool_log.dart';
import 'package:orion/features/providers/data/fake_provider_repository.dart';
import 'package:orion/features/providers/domain/provider_presets.dart';

import '../../tool/mock_device/board.dart';
import '../../tool/mock_device/harness_client.dart';
import '../../tool/mock_device/tool_script.dart';
import '../support/stub_tools.dart';

const _token = 'loop-token';

/// The whole demo with no hardware: the mock board decides to call a tool,
/// the desktop harness runs it, and the answer comes back as the board's
/// spoken reply.
void main() {
  late StubTools tools;
  late ConfirmationQueue queue;
  late DesktopHarnessRepository harness;
  late FakeDeviceClient device;
  late MockBoard board;
  late Directory temp;
  final clients = <HarnessClient>[];

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('orion_loop');
    tools = StubTools();
    queue = ConfirmationQueue(timeout: const Duration(seconds: 30));
    device = FakeDeviceClient(autoTurns: false);
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
      pairingToken: _token,
      port: 0,
    );
    harness = created;
    await harness.setEnabled(true);

    board = MockBoard();
    // What POST /api/config does when the desktop turns PC control on.
    board.mergeConfig(<String, dynamic>{
      'pc': <String, dynamic>{
        'enabled': true,
        'base_url': 'http://127.0.0.1:${harness.server.boundPort}',
        'token': _token,
      },
    });
    HarnessClient client() {
      final pc = board.config['pc']! as Map<String, dynamic>;
      final made = HarnessClient(
        baseUrl: pc['base_url']! as String,
        token: pc['token'] as String?,
      );
      clients.add(made);
      return made;
    }

    board.availableTools = () => client().toolNames();
    board.onToolCall = (callId, turnId, name, args, approval, onUpdate) =>
        client().call(
          callId: callId,
          turnId: turnId,
          name: name,
          args: args,
          approval: approval,
          onUpdate: onUpdate,
        );
  });

  tearDown(() async {
    for (final client in clients) {
      client.close();
    }
    clients.clear();
    await board.dispose();
    await harness.dispose();
    device.dispose();
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows holds the log file a moment longer. Temp is temp.
    }
  });

  test('a safe tool runs on the PC and becomes the spoken reply', () async {
    final events = <Map<String, dynamic>>[];
    final sub = board.events.listen(events.add);

    await board.runTurn('t_1', source: 'app', text: 'open spotify');
    await sub.cancel();

    final toolEvents = events.where((e) => e['type'] == 'turn.tool').toList();
    expect(toolEvents, hasLength(greaterThanOrEqualTo(2)));
    expect(
      (toolEvents.first['call']! as Map<String, dynamic>)['status'],
      'pending',
    );
    final last = toolEvents.last['call']! as Map<String, dynamic>;
    expect(last['name'], 'open_app');
    expect(last['status'], 'done');
    expect(last['result'], 'Opened spotify');
    expect(tools.calls, <String>['openApp:spotify']);

    final reply = events.firstWhere((e) => e['type'] == 'turn.reply');
    expect(reply['text'], 'Opened spotify');
  });

  test('a confirm tool waits for the user, then the board hears it', () async {
    final events = <Map<String, dynamic>>[];
    final sub = board.events.listen(events.add);

    final turn = board.runTurn('t_2', source: 'app', text: 'lock my pc');
    await _until(() => queue.current.isNotEmpty);
    expect(queue.current.single.toolCall.name, 'lock_pc');
    expect(tools.calls, isEmpty, reason: 'nothing runs before approval');

    await harness.approve(queue.current.single.id);
    await turn;
    await sub.cancel();

    final statuses = events
        .where((e) => e['type'] == 'turn.tool')
        .map((e) => (e['call']! as Map<String, dynamic>)['status'])
        .toList();
    expect(statuses, contains('pending_confirmation'));
    expect(statuses.last, 'done');
    expect(tools.calls, <String>['lockPc']);
    final reply = events.firstWhere((e) => e['type'] == 'turn.reply');
    expect(reply['text'], 'Locked the workstation');
  });

  test('deny comes back as the board saying no', () async {
    final events = <Map<String, dynamic>>[];
    final sub = board.events.listen(events.add);

    final turn = board.runTurn('t_3', source: 'app', text: 'find my notes');
    await _until(() => queue.current.isNotEmpty);
    await harness.deny(queue.current.single.id);
    await turn;
    await sub.cancel();

    final last = events.lastWhere((e) => e['type'] == 'turn.tool')['call']!;
    expect((last as Map<String, dynamic>)['status'], 'denied');
    final reply = events.firstWhere((e) => e['type'] == 'turn.reply');
    expect(reply['text'], 'denied by user');
  });

  test('PC control off means the board calls nothing at all', () async {
    await harness.setEnabled(false);
    board.mergeConfig(<String, dynamic>{
      'pc': <String, dynamic>{'enabled': false},
    });
    final events = <Map<String, dynamic>>[];
    final sub = board.events.listen(events.add);

    await board.runTurn('t_4', source: 'app', text: 'open spotify');
    await sub.cancel();

    expect(events.where((e) => e['type'] == 'turn.tool'), isEmpty);
    expect(tools.calls, isEmpty);
  });

  group('tool script', () {
    const available = <String>{
      'open_app',
      'lock_pc',
      'system_stats',
      'screenshot',
      'search_files',
      'media',
      'agent_task',
    };

    MockToolCall? pick(String text, {int turn = 43}) => ToolScript.forText(
      text,
      pcEnabled: true,
      turnCounter: turn,
      available: available,
    );

    test('reads the obvious phrases out of a transcript', () {
      expect(pick('open spotify')?.args['name'], 'spotify');
      expect(pick('find my tax return')?.name, 'search_files');
      expect(pick('lock my pc')?.name, 'lock_pc');
      expect(pick('how hot is the gpu')?.name, 'system_stats');
      expect(pick('what is on my screen')?.name, 'screenshot');
      expect(pick('skip this one')?.args['action'], 'next');
      expect(pick('tidy my downloads folder')?.name, 'agent_task');
    });

    test('offers nothing the desktop did not list', () {
      expect(
        ToolScript.forText(
          'open spotify',
          pcEnabled: true,
          turnCounter: 43,
          available: const <String>{'system_stats'},
        ),
        isNull,
      );
    });

    test('PC control off means no tool, ever', () {
      expect(
        ToolScript.forText(
          'open spotify',
          pcEnabled: false,
          turnCounter: 42,
          available: available,
        ),
        isNull,
      );
    });

    test('with nothing to match it opens an app every third turn', () {
      expect(pick('hello there', turn: 42)?.name, 'open_app');
      expect(pick('hello there', turn: 43), isNull);
    });
  });
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 100 && !ready(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
