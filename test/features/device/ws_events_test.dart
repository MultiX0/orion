import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:orion/features/conversation/domain/tool_call_status.dart';
import 'package:orion/features/device/domain/device_mode.dart';
import 'package:orion/features/device/domain/turn_source.dart';
import 'package:orion/features/device/domain/ws_event.dart';

/// One line per event in docs/DEVICE_PROTOCOL.md, copied from the doc.
void main() {
  final lines = File(
    'test/fixtures/ws_events.jsonl',
  ).readAsLinesSync().where((l) => l.trim().isNotEmpty).toList();

  List<WsEvent> parseAll() => [
    for (final line in lines)
      WsEvent.fromJson(jsonDecode(line) as Map<String, dynamic>),
  ];

  test('every event type in the protocol parses', () {
    final events = parseAll();
    expect(events, hasLength(12));
    expect(events.map((e) => e.runtimeType).toSet(), hasLength(11));
    for (final event in events) {
      expect(event.ts, isNotNull, reason: 'ts is on every event');
    }
  });

  test('state carries the mode the orb reads', () {
    final state = parseAll().whereType<WsStateEvent>().single;
    expect(state.mode, DeviceMode.listening);
    expect(state.wifiRssi, -50);
    expect(state.volume, 70);
    expect(state.muted, isFalse);
    expect(state.wakeWordEnabled, isNull, reason: 'absent means unchanged');
  });

  test('turn events carry the turn id and the text', () {
    final events = parseAll();
    expect(events.whereType<WsTurnStartEvent>().single.source, TurnSource.wake);
    expect(
      events.whereType<WsTurnTranscriptEvent>().single.text,
      'what time is it',
    );
    expect(
      events.whereType<WsTurnReplyEvent>().single.text,
      'It is ten past nine.',
    );
    expect(events.whereType<WsTurnEndEvent>().single.timingsMs?.total, 4100);
  });

  test('a tool result delta parses without name or args', () {
    final tools = parseAll().whereType<WsTurnToolEvent>().toList();
    expect(tools, hasLength(2));

    final pending = tools.first.toolCall;
    expect(pending.name, 'open_app');
    expect(pending.args['name'], 'spotify');
    expect(pending.status, ToolCallStatus.pending);

    final done = tools.last.toolCall;
    expect(done.id, 'c1');
    expect(done.status, ToolCallStatus.done);
    expect(done.result, 'ok');
    expect(done.name, isEmpty, reason: 'the delta only sends what changed');
  });

  test('error and log parse', () {
    final events = parseAll();
    expect(events.whereType<WsErrorEvent>().single.code, 'llm_401');
    expect(events.whereType<WsLogEvent>().single.level, 'info');
    expect(events.whereType<WsPongEvent>(), hasLength(1));
  });

  test('an unknown type throws instead of guessing', () {
    expect(
      () => WsEvent.fromJson(const <String, dynamic>{'type': 'turn.dance'}),
      throwsA(isA<Object>()),
    );
  });
}
