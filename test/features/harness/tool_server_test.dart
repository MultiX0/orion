import 'dart:convert';
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
import 'package:web_socket_channel/io.dart';

import '../../support/stub_tools.dart';

const _token = 'tok-123';

void main() {
  late StubTools tools;
  late ConfirmationQueue queue;
  late DesktopHarnessRepository repo;
  late FakeDeviceClient device;
  late Directory temp;
  late HttpClient http;

  Future<Map<String, dynamic>> post(
    String body, {
    String? token = _token,
  }) async {
    final request = await http.post(
      '127.0.0.1',
      repo.server.boundPort!,
      '/tool',
    );
    if (token != null) request.headers.set('X-Orion-Token', token);
    request.write(body);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return <String, dynamic>{
      'status_code': response.statusCode,
      ...?(jsonDecode(text) as Map<String, dynamic>?),
    };
  }

  Future<Map<String, dynamic>> get(
    String path, {
    String? token = _token,
  }) async {
    final request = await http.get('127.0.0.1', repo.server.boundPort!, path);
    if (token != null) request.headers.set('X-Orion-Token', token);
    final response = await request.close();
    final text = await response.transform(utf8.decoder).join();
    return <String, dynamic>{
      'status_code': response.statusCode,
      ...?(jsonDecode(text) as Map<String, dynamic>?),
    };
  }

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('orion_tools');
    tools = StubTools();
    queue = ConfirmationQueue(timeout: const Duration(seconds: 30));
    device = FakeDeviceClient(autoTurns: false);
    http = HttpClient();
    late DesktopHarnessRepository created;
    final executor = ToolExecutor(
      tools: tools,
      agent: const NullRuntime(),
      queue: queue,
      brain: () async => (ProviderPresets.deepinfra, 'some-model'),
      localApproval: () => created.approvalMode,
      describe: FakeProviderRepository(),
      onUpdate: (call) => created.record(call),
      onAgentLog: (jobId, line) => created.recordAgentLog(jobId, line),
    );
    created = DesktopHarnessRepository(
      executor: executor,
      queue: queue,
      agent: const NullRuntime(),
      deviceClient: device,
      log: ToolLog('${temp.path}/tools.jsonl'),
      pairingToken: _token,
      port: 0,
    );
    repo = created;
    await repo.setEnabled(true);
  });

  tearDown(() async {
    http.close(force: true);
    await repo.dispose();
    device.dispose();
    try {
      temp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows still holds the log file for a moment. Temp is temp.
    }
  });

  test('every route needs the paired token', () async {
    expect((await get('/tools', token: null))['status_code'], 401);
    expect((await get('/tools', token: 'wrong'))['status_code'], 401);
    expect((await get('/tools'))['status_code'], 200);
  });

  test('GET /tools offers the native tools and hides agent_task', () async {
    final body = await get('/tools');
    final names = (body['tools']! as List)
        .cast<Map<String, dynamic>>()
        .map((t) => (t['function']! as Map<String, dynamic>)['name'])
        .toList();

    expect(names, contains('open_app'));
    expect(names, contains('system_stats'));
    expect(
      names,
      isNot(contains('agent_task')),
      reason: 'no dsh on this machine, so the LLM never sees the tool',
    );
  });

  test('a safe tool runs at once and says what it did', () async {
    final body = await post(
      '{"call_id":"c1","turn_id":"t1","name":"open_app",'
      '"args":{"name":"spotify"}}',
    );

    expect(body['status'], 'done');
    expect(body['result'], 'Opened spotify');
    expect(tools.calls, <String>['openApp:spotify']);
  });

  test('a confirm tool waits, then runs when the user approves', () async {
    final body = await post('{"call_id":"c2","name":"lock_pc"}');

    expect(body['status'], 'pending_confirmation');
    expect(body['confirm_id'], 'kc2');
    expect(tools.calls, isEmpty);

    await repo.approve('kc2', alwaysAllowThisSession: true);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(tools.calls, <String>['lockPc']);
    expect((await get('/tool/c2'))['status'], 'done');

    // Ticked "always allow", so the second one does not ask.
    expect((await post('{"call_id":"c3","name":"lock_pc"}'))['status'], 'done');
  });

  test('deny tells the board the user said no', () async {
    await post('{"call_id":"c4","name":"screenshot"}');
    await repo.deny('kc4');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final body = await get('/tool/c4');
    expect(body['status'], 'denied');
    expect(body['message'], 'denied by user');
  });

  test('a tool that throws becomes an error, not a dead call', () async {
    tools.lockFails = true;
    await post('{"call_id":"c5","name":"lock_pc"}');
    await repo.approve('kc5');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final body = await get('/tool/c5');
    expect(body['status'], 'error');
    expect(body['message'], 'The screen said no');
  });

  test('an unknown tool and bad JSON both answer, never hang', () async {
    expect(
      (await post('{"call_id":"c6","name":"eat_lunch"}'))['status'],
      'error',
    );
    expect((await post('not json'))['status_code'], 400);
    expect((await get('/tool/nope'))['status_code'], 404);
  });

  test('the WS pushes tool.update as the call moves', () async {
    final socket = IOWebSocketChannel.connect(
      Uri.parse('ws://127.0.0.1:${repo.server.boundPort}/ws?token=$_token'),
    );
    await socket.ready;
    final seen = <Map<String, dynamic>>[];
    socket.stream.listen(
      (m) => seen.add(jsonDecode('$m') as Map<String, dynamic>),
    );

    await post('{"call_id":"c7","name":"system_stats"}');
    await Future<void>.delayed(const Duration(milliseconds: 60));
    await socket.sink.close();

    expect(seen.map((e) => e['type']), everyElement('tool.update'));
    expect(seen.last['call_id'], 'c7');
    expect(seen.last['status'], 'done');
  });

  test('every call lands in tools.jsonl', () async {
    await post('{"call_id":"c8","name":"media","args":{"action":"next"}}');
    final file = File('${temp.path}/tools.jsonl');

    // The log is written after the answer goes out, on purpose.
    // Poll until the finished line is there; a line caught half written
    // is skipped and read again on the next pass.
    var lines = <Map<String, dynamic>>[];
    bool landed() => lines.isNotEmpty && lines.last['status'] == 'done';
    for (var i = 0; i < 200 && !landed(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      if (!file.existsSync()) continue;
      try {
        lines = file
            .readAsLinesSync()
            .where((l) => l.trim().isNotEmpty)
            .map((l) => jsonDecode(l) as Map<String, dynamic>)
            .toList();
      } on FormatException {
        continue;
      } on FileSystemException {
        continue;
      }
    }

    expect(lines.last['call_id'], 'c8');
    expect(lines.last['name'], 'media');
    expect(lines.last['status'], 'done');
    expect(lines.last['args'], <String, dynamic>{'action': 'next'});
    expect(lines.last['ts'], isNotNull);
  });

  test('turning PC control off stops the port and clears the queue', () async {
    await post('{"call_id":"c9","name":"screenshot"}');
    expect(queue.current, hasLength(1));

    await repo.setEnabled(false);

    expect(repo.server.isRunning, isFalse);
    expect(queue.current, isEmpty);
    final status = await repo.status.first;
    expect(status.isEnabled, isFalse);
  });
}
